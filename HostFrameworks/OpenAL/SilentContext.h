// Included inside OpenAL.mm's private namespace, after the packet helpers.
// Simulator-only, clocked null renderer. No native AL rendering calls or audio
// device activation: ALmixer still observes queues and playback completion.
using SilentProperties = std::unordered_map<ALenum, std::vector<double>>;

struct SilentBuffer {
    ALint size = 0, frequency = 0, bits = 16, channels = 1;
    double duration() const {
        return frequency ? double(size) / (double(frequency) * channels * (bits / 8.0)) : 0;
    }
};
struct SilentSource {
    ALenum state = AL_INITIAL, type = AL_UNDETERMINED;
    std::vector<ALuint> queue;
    size_t cursor = 0;
    double position = 0, updated = 0;
    bool seekPending = false;
    SilentProperties properties = {
        {AL_PITCH, {1}}, {AL_GAIN, {1}}, {AL_MIN_GAIN, {0}}, {AL_MAX_GAIN, {1}},
        {AL_MAX_DISTANCE, {FLT_MAX}}, {AL_ROLLOFF_FACTOR, {1}},
        {AL_REFERENCE_DISTANCE, {1}}, {AL_CONE_INNER_ANGLE, {360}},
        {AL_CONE_OUTER_ANGLE, {360}}, {AL_CONE_OUTER_GAIN, {0}},
        {AL_POSITION, {0,0,0}}, {AL_VELOCITY, {0,0,0}},
        {AL_DIRECTION, {0,0,0}}, {AL_LOOPING, {0}}, {AL_SOURCE_RELATIVE, {0}},
    };
    bool looping() const { return properties.at(AL_LOOPING)[0] != 0; }
};
struct SilentDevice {
    ALuint nextBuffer = 1;
    std::unordered_map<ALuint, SilentBuffer> buffers;
};
struct SilentContext {
    ALCdevice *device = nullptr;
    ALenum error = AL_NO_ERROR;
    ALuint nextSource = 1;
    bool suspended = false;
    std::unordered_map<ALuint, SilentSource> sources;
    SilentProperties listener = {{AL_GAIN,{1}}, {AL_POSITION,{0,0,0}},
        {AL_VELOCITY,{0,0,0}}, {AL_ORIENTATION,{0,0,-1,0,1,0}}};
    SilentProperties globals = {{AL_DOPPLER_FACTOR,{1}},
        {AL_DOPPLER_VELOCITY,{1}}, {AL_SPEED_OF_SOUND,{343.3}},
        {AL_DISTANCE_MODEL,{AL_INVERSE_DISTANCE_CLAMPED}}};
    void fail(ALenum value) { if(error == AL_NO_ERROR) error = value; }
};
std::mutex gSilentMutex;
std::unordered_map<uint32_t, SilentContext> gSilentContexts;
std::unordered_map<ALCdevice *, SilentDevice> gSilentDevices;

static double SilentNow() {
    return std::chrono::duration<double>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

static void AdvanceSilentSource(SilentSource &s, const SilentDevice &device,
                                double now, bool suspended) {
    const double elapsed = std::max(0.0, now - s.updated);
    s.updated = now;
    if(s.state != AL_PLAYING || suspended) return;
    double total = 0;
    for(ALuint id : s.queue) if(id) total += device.buffers.at(id).duration();
    if(total <= 0) {
        s.state = AL_STOPPED;
        s.cursor = s.queue.size();
        s.position = 0;
        return;
    }
    s.position += elapsed * s.properties.at(AL_PITCH)[0];
    // Bound work even after a long sleep with a very short looping buffer.
    if(s.looping()) s.position = fmod(s.position, total);
    while(s.cursor < s.queue.size()) {
        ALuint id = s.queue[s.cursor];
        double duration = id ? device.buffers.at(id).duration() : 0;
        if(s.position < duration) return;
        s.position -= duration;
        if(++s.cursor == s.queue.size() && s.looping()) s.cursor = 0;
    }
    s.state = AL_STOPPED;
    s.position = 0;
}

static bool SilentBufferInUse(ALCdevice *device, ALuint id) {
    for(auto &entry : gSilentContexts) if(entry.second.device == device)
        for(auto &source : entry.second.sources)
            if(std::find(source.second.queue.begin(), source.second.queue.end(), id)
                != source.second.queue.end()) return true;
    return false;
}

static void SuspendSilentContext(uint32_t token, bool suspend) {
    std::lock_guard<std::mutex> lock(gSilentMutex);
    auto it = gSilentContexts.find(token);
    if(it == gSilentContexts.end()) return;
    auto &c = it->second;
    const double now = SilentNow();
    for(auto &entry : c.sources)
        AdvanceSilentSource(entry.second, gSilentDevices.at(c.device), now, c.suspended);
    c.suspended = suspend;
}

// The six scalar/vector API variants share the same packet layout. Keep
// integer/float conversion here rather than duplicating each AL entry point.
static bool SilentPropertyPacket(LC32OpenALPacket &packet, unsigned variant,
        bool get, unsigned parameterWord, std::vector<double> &values) {
    uint32_t *w = packet.words;
    const bool integer = variant >= 3;
    const unsigned form = variant % 3; // scalar, three scalars, pointer
    const unsigned first = parameterWord + 1;
    for(size_t i = 0; i < values.size(); ++i) {
        uint32_t word = 0;
        if(!get) {
            if(form == 2) {
                uint64_t address = uint64_t(w[first]) + 4 * i;
                if(address > UINT32_MAX || !ReadGuest(address, &word, 4)) return false;
            } else word = w[first + i];
            values[i] = integer ? double(int32_t(word)) : WordToFloat(word);
        } else {
            // Clamp integer conversion; NaN/overflow must not invoke C++ UB.
            word = integer ? uint32_t(int32_t(std::max(double(INT32_MIN),
                std::min(double(INT32_MAX), values[i])))) : FloatToWord(values[i]);
            uint64_t address = form == 1 ? w[first + i] : uint64_t(w[first]) + 4 * i;
            if(address > UINT32_MAX || !WriteGuest(address, &word, 4)) return false;
        }
    }
    return true;
}

static bool SilentSourceProperty(SilentContext &c, SilentDevice &d,
        SilentSource &s, ALenum parameter, bool get, std::vector<double> &v) {
    if(parameter == AL_BUFFER) {
        if(get) { v[0] = s.type == AL_STATIC && !s.queue.empty() ? s.queue[0] : 0; return true; }
        if(s.state == AL_PLAYING || s.state == AL_PAUSED) { c.fail(AL_INVALID_OPERATION); return false; }
        if(v[0] < 0 || v[0] > UINT32_MAX || floor(v[0]) != v[0]) { c.fail(AL_INVALID_VALUE); return false; }
        ALuint id = v[0];
        if(id && !d.buffers.count(id)) { c.fail(AL_INVALID_VALUE); return false; }
        s.queue.clear();
        if(id) s.queue.push_back(id);
        s.type = id ? AL_STATIC : AL_UNDETERMINED;
        s.cursor = 0; s.position = 0; s.seekPending = false;
        return true;
    }
    if(parameter == AL_SOURCE_STATE || parameter == AL_SOURCE_TYPE ||
       parameter == AL_BUFFERS_QUEUED || parameter == AL_BUFFERS_PROCESSED) {
        if(!get) { c.fail(AL_INVALID_OPERATION); return false; }
        if(parameter == AL_SOURCE_STATE) v[0] = s.state;
        if(parameter == AL_SOURCE_TYPE) v[0] = s.type;
        if(parameter == AL_BUFFERS_QUEUED) v[0] = s.queue.size();
        if(parameter == AL_BUFFERS_PROCESSED) v[0] = s.looping() ? 0 : s.cursor;
        return true;
    }
    if(parameter == AL_SEC_OFFSET || parameter == AL_SAMPLE_OFFSET || parameter == AL_BYTE_OFFSET) {
        const SilentBuffer *buffer = nullptr;
        for(ALuint id : s.queue) if(id) { buffer = &d.buffers.at(id); break; }
        const double units = parameter == AL_SEC_OFFSET ? 1 : buffer ?
            buffer->frequency * (parameter == AL_BYTE_OFFSET ? buffer->channels * buffer->bits / 8.0 : 1) : 0;
        if(get) {
            double offset = s.position;
            if(s.state == AL_PLAYING || s.state == AL_PAUSED)
                for(size_t i = 0; i < s.cursor; ++i) if(s.queue[i]) offset += d.buffers.at(s.queue[i]).duration();
            v[0] = offset * units;
            return true;
        }
        if(v[0] < 0 || !units || !buffer) { c.fail(AL_INVALID_VALUE); return false; }
        double offset = v[0] / units;
        size_t cursor = 0;
        for(; cursor < s.queue.size(); ++cursor) {
            double duration = s.queue[cursor] ? d.buffers.at(s.queue[cursor]).duration() : 0;
            if(offset < duration) break;
            offset -= duration;
        }
        if(cursor == s.queue.size()) { c.fail(AL_INVALID_VALUE); return false; }
        s.cursor = cursor; s.position = offset;
        s.seekPending = s.state == AL_INITIAL || s.state == AL_STOPPED;
        return true;
    }
    auto it = s.properties.find(parameter);
    if(it == s.properties.end()) { c.fail(AL_INVALID_ENUM); return false; }
    if(get) { v = it->second; return true; }
    bool valid = true;
    if(v.size() == 1) {
        if(parameter == AL_LOOPING || parameter == AL_SOURCE_RELATIVE) valid = v[0] == 0 || v[0] == 1;
        else if(parameter == AL_PITCH) valid = v[0] > 0;
        else valid = v[0] >= 0;
        if(parameter == AL_MIN_GAIN || parameter == AL_MAX_GAIN || parameter == AL_CONE_OUTER_GAIN) valid &= v[0] <= 1;
        if(parameter == AL_CONE_INNER_ANGLE || parameter == AL_CONE_OUTER_ANGLE) valid &= v[0] <= 360;
    }
    if(!valid) { c.fail(AL_INVALID_VALUE); return false; }
    it->second = v;
    return true;
}

static bool DispatchSilentAL(uint32_t opcode, LC32OpenALPacket &packet) {
    std::lock_guard<std::mutex> lock(gSilentMutex);
    uint32_t *w = packet.words;
    if(opcode == LC32_OPENAL_OP_alGetEnumValue) {
        std::string name;
        w[0] = ReadGuestCString(w[0], &name) ? alGetEnumValue(name.c_str()) : 0;
        return true;
    }
    const uint32_t token = gSilentCurrentContextToken.load();
    bool valid = false;
    ALCcontext *context = ContextForToken(token, &valid);
    if(!valid || !context) {
        // AL has no usable state without a context. Never leak to native AL.
        w[0] = opcode == LC32_OPENAL_OP_alGetError ? AL_INVALID_OPERATION : 0;
        return true;
    }
    SilentContext &c = gSilentContexts[token];
    c.device = alcGetContextsDevice(context);
    SilentDevice &d = gSilentDevices[c.device];
    const double now = SilentNow();
    auto source = c.sources.find(w[0]);
    if(source != c.sources.end()) AdvanceSilentSource(source->second, d, now, c.suspended);

    // Listener, source and buffer property families each have six setters
    // followed by the corresponding six getters in the wire protocol.
    unsigned base = 0, parameterWord = 0;
    if(opcode >= LC32_OPENAL_OP_alListenerf && opcode <= LC32_OPENAL_OP_alGetListeneriv)
        base = LC32_OPENAL_OP_alListenerf;
    if(opcode >= LC32_OPENAL_OP_alSourcef && opcode <= LC32_OPENAL_OP_alGetSourceiv)
        base = LC32_OPENAL_OP_alSourcef, parameterWord = 1;
    if(opcode >= LC32_OPENAL_OP_alBufferf && opcode <= LC32_OPENAL_OP_alGetBufferiv)
        base = LC32_OPENAL_OP_alBufferf, parameterWord = 1;
    if(base) {
        const bool get = opcode - base >= 6;
        const unsigned variant = (opcode - base) % 6;
        const ALenum parameter = w[parameterWord];
        const size_t count = base == LC32_OPENAL_OP_alListenerf ? ListenerVectorCount(parameter) :
            base == LC32_OPENAL_OP_alSourcef ? SourceVectorCount(parameter) : 1;
        if((variant % 3 == 0 && count != 1) || (variant % 3 == 1 && count != 3)) {
            c.fail(AL_INVALID_ENUM); return true;
        }
        std::vector<double> values(count);
        if(!get && !SilentPropertyPacket(packet, variant, false, parameterWord, values)) return false;
        for(double value : values) if(!std::isfinite(value)) { c.fail(AL_INVALID_VALUE); return true; }
        if(base == LC32_OPENAL_OP_alSourcef) {
            if(source == c.sources.end()) { c.fail(AL_INVALID_NAME); return true; }
            if(!SilentSourceProperty(c, d, source->second, parameter, get, values)) return true;
        } else if(base == LC32_OPENAL_OP_alListenerf) {
            auto it = c.listener.find(parameter);
            if(it == c.listener.end()) { c.fail(AL_INVALID_ENUM); return true; }
            if(get) values = it->second;
            else if(parameter == AL_GAIN && values[0] < 0) { c.fail(AL_INVALID_VALUE); return true; }
            else it->second = values;
        } else {
            auto it = d.buffers.find(w[0]);
            if(it == d.buffers.end()) { c.fail(AL_INVALID_NAME); return true; }
            if(!get) { c.fail(AL_INVALID_ENUM); return true; }
            switch(parameter) {
                case AL_FREQUENCY: values[0] = it->second.frequency; break;
                case AL_SIZE: values[0] = it->second.size; break;
                case AL_BITS: values[0] = it->second.bits; break;
                case AL_CHANNELS: values[0] = it->second.channels; break;
                default: c.fail(AL_INVALID_ENUM); return true;
            }
        }
        return !get || SilentPropertyPacket(packet, variant, true, parameterWord, values);
    }

    if(opcode >= LC32_OPENAL_OP_alSourcePlayv && opcode <= LC32_OPENAL_OP_alSourcePause) {
        const bool vector = opcode <= LC32_OPENAL_OP_alSourcePausev;
        std::vector<ALuint> ids;
        if(vector) {
            if(int32_t(w[0]) < 0) { c.fail(AL_INVALID_VALUE); return true; }
            if(!ReadGuestArray(w[1], int32_t(w[0]), &ids)) return false;
        } else ids.push_back(w[0]);
        for(ALuint id : ids) if(!c.sources.count(id)) { c.fail(AL_INVALID_NAME); return true; }
        const unsigned action = opcode - (vector ? LC32_OPENAL_OP_alSourcePlayv : LC32_OPENAL_OP_alSourcePlay);
        for(ALuint id : ids) {
            auto &s = c.sources.at(id);
            AdvanceSilentSource(s, d, now, c.suspended);
            if(action == 0) {
                if(s.state != AL_PAUSED && !s.seekPending) s.cursor = 0, s.position = 0;
                s.seekPending = false;
                s.state = AL_PLAYING;
                AdvanceSilentSource(s, d, now, c.suspended);
            } else if(action == 1) {
                s.seekPending = false;
                if(s.state != AL_INITIAL) s.state = AL_STOPPED, s.cursor = s.queue.size(), s.position = 0;
            } else if(action == 2) {
                s.state = AL_INITIAL; s.cursor = 0; s.position = 0; s.seekPending = false;
            }
            else if(s.state == AL_PLAYING) s.state = AL_PAUSED;
        }
        return true;
    }

    switch(opcode) {
        case LC32_OPENAL_OP_alGetError: w[0] = c.error; c.error = AL_NO_ERROR; break;
        case LC32_OPENAL_OP_alIsEnabled:
            c.fail(AL_INVALID_ENUM); w[0] = AL_FALSE; break;
        case LC32_OPENAL_OP_alGenSources:
        case LC32_OPENAL_OP_alGenBuffers: {
            const bool sources = opcode == LC32_OPENAL_OP_alGenSources;
            const int32_t count = w[0];
            const size_t limit = sources ? 256 : 65536;
            const size_t used = sources ? c.sources.size() : d.buffers.size();
            if(count < 0) { c.fail(AL_INVALID_VALUE); break; }
            ALuint &next = sources ? c.nextSource : d.nextBuffer;
            if(size_t(count) > limit - used || uint64_t(next) + count > UINT32_MAX) { c.fail(AL_OUT_OF_MEMORY); break; }
            std::vector<ALuint> ids(count);
            for(int32_t i = 0; i < count; ++i) ids[i] = next + i;
            if(!WriteGuestArray(w[1], ids)) return false;
            for(ALuint id : ids) {
                if(sources) c.sources.emplace(id, SilentSource{});
                else d.buffers.emplace(id, SilentBuffer{});
            }
            next += count;
            break;
        }
        case LC32_OPENAL_OP_alDeleteSources:
        case LC32_OPENAL_OP_alDeleteBuffers: {
            const bool sources = opcode == LC32_OPENAL_OP_alDeleteSources;
            if(int32_t(w[0]) < 0) { c.fail(AL_INVALID_VALUE); break; }
            std::vector<ALuint> ids;
            if(!ReadGuestArray(w[1], int32_t(w[0]), &ids)) return false;
            for(ALuint id : ids) {
                if(sources ? !c.sources.count(id) : id && !d.buffers.count(id)) { c.fail(AL_INVALID_NAME); return true; }
                if(!sources && id && SilentBufferInUse(c.device, id)) { c.fail(AL_INVALID_OPERATION); return true; }
            }
            for(ALuint id : ids) { if(sources) c.sources.erase(id); else d.buffers.erase(id); }
            break;
        }
        case LC32_OPENAL_OP_alIsSource: w[0] = c.sources.count(w[0]) != 0; break;
        case LC32_OPENAL_OP_alIsBuffer: w[0] = w[0] == 0 || d.buffers.count(w[0]) != 0; break;
        case LC32_OPENAL_OP_alBufferData: {
            auto it = d.buffers.find(w[0]);
            if(it == d.buffers.end()) { c.fail(AL_INVALID_NAME); break; }
            if(SilentBufferInUse(c.device, w[0])) { c.fail(AL_INVALID_OPERATION); break; }
            const unsigned frameBytes = BytesPerCaptureSample(w[1]);
            if(!frameBytes) { c.fail(AL_INVALID_ENUM); break; }
            if(int32_t(w[3]) < 0 || w[3] > kMaxGuestTransfer || int32_t(w[4]) <= 0 || w[3] % frameBytes) { c.fail(AL_INVALID_VALUE); break; }
            // Validate/copy guest storage in bounded pieces, but don't retain
            // PCM that a null renderer never consumes.
            char bytes[4096];
            for(uint32_t offset = 0; offset < w[3];) {
                uint32_t count = std::min(uint32_t(sizeof(bytes)), w[3] - offset);
                uint64_t address = uint64_t(w[2]) + offset;
                if(address + count > (UINT64_C(1) << 32) || !ReadGuest(address, bytes, count)) return false;
                offset += count;
            }
            it->second = {int32_t(w[3]), int32_t(w[4]),
                (w[1] == AL_FORMAT_MONO8 || w[1] == AL_FORMAT_STEREO8) ? 8 : 16,
                (w[1] == AL_FORMAT_MONO8 || w[1] == AL_FORMAT_MONO16) ? 1 : 2};
            break;
        }
        case LC32_OPENAL_OP_alSourceQueueBuffers:
        case LC32_OPENAL_OP_alSourceUnqueueBuffers: {
            if(source == c.sources.end()) { c.fail(AL_INVALID_NAME); break; }
            auto &s = source->second;
            int32_t count = w[1];
            if(count < 0) { c.fail(AL_INVALID_VALUE); break; }
            if(count == 0) break;
            if(opcode == LC32_OPENAL_OP_alSourceQueueBuffers) {
                if(s.type == AL_STATIC) { c.fail(AL_INVALID_OPERATION); break; }
                if(size_t(count) > 65536 - s.queue.size()) { c.fail(AL_OUT_OF_MEMORY); break; }
                std::vector<ALuint> ids;
                if(!ReadGuestArray(w[2], count, &ids)) return false;
                const SilentBuffer *format = nullptr;
                for(ALuint id : s.queue) if(id) { format = &d.buffers.at(id); break; }
                for(ALuint id : ids) if(id) {
                    auto it = d.buffers.find(id);
                    if(it == d.buffers.end()) { c.fail(AL_INVALID_NAME); return true; }
                    if(format && (format->frequency != it->second.frequency || format->bits != it->second.bits || format->channels != it->second.channels)) { c.fail(AL_INVALID_OPERATION); return true; }
                    format = &it->second;
                }
                s.queue.insert(s.queue.end(), ids.begin(), ids.end());
                s.type = AL_STREAMING;
                if(s.state == AL_STOPPED) s.cursor = s.queue.size();
            } else {
                if(s.type != AL_STREAMING || s.looping() || size_t(count) > s.cursor) { c.fail(AL_INVALID_VALUE); break; }
                std::vector<ALuint> ids(s.queue.begin(), s.queue.begin() + count);
                if(!WriteGuestArray(w[2], ids)) return false;
                s.queue.erase(s.queue.begin(), s.queue.begin() + count);
                s.cursor -= count;
            }
            break;
        }
        case LC32_OPENAL_OP_alGetString: {
            const char *value = nullptr;
            switch(w[0]) {
                case AL_VENDOR: value = "LiveExec32"; break;
                case AL_RENDERER: value = "Simulator silent renderer"; break;
                case AL_VERSION: value = "1.1"; break;
                case AL_EXTENSIONS: value = "AL_EXT_STATIC_BUFFER"; break;
                case AL_NO_ERROR: value = "No Error"; break;
                case AL_INVALID_NAME: value = "Invalid Name"; break;
                case AL_INVALID_ENUM: value = "Invalid Enum"; break;
                case AL_INVALID_VALUE: value = "Invalid Value"; break;
                case AL_INVALID_OPERATION: value = "Invalid Operation"; break;
                case AL_OUT_OF_MEMORY: value = "Out of Memory"; break;
                default: c.fail(AL_INVALID_ENUM); break;
            }
            CopyStringResult(&packet, value, false, 1, 2);
            break;
        }
        case LC32_OPENAL_OP_alGetBooleanv: case LC32_OPENAL_OP_alGetIntegerv:
        case LC32_OPENAL_OP_alGetFloatv: case LC32_OPENAL_OP_alGetDoublev:
        case LC32_OPENAL_OP_alGetBoolean: case LC32_OPENAL_OP_alGetInteger:
        case LC32_OPENAL_OP_alGetFloat: case LC32_OPENAL_OP_alGetDouble: {
            auto it = c.globals.find(w[0]);
            if(it == c.globals.end()) { c.fail(AL_INVALID_ENUM); break; }
            double value = it->second[0];
            const unsigned kind = (opcode - LC32_OPENAL_OP_alGetBooleanv) % 4;
            const bool pointer = opcode < LC32_OPENAL_OP_alGetBoolean;
            uint32_t destination = w[1];
            uint32_t result = kind == 0 ? value != 0 : kind == 1 ?
                uint32_t(int32_t(std::min(double(INT32_MAX), value))) : FloatToWord(value);
            if(pointer) {
                if(kind == 3) { if(!WriteGuest(destination, &value, 8)) return false; }
                else if(!WriteGuest(destination, &result, kind == 0 ? 1 : 4)) return false;
            } else if(kind == 3) SetDoubleResult(&packet, value);
            else w[0] = result;
            break;
        }
        case LC32_OPENAL_OP_alDopplerFactor: case LC32_OPENAL_OP_alDopplerVelocity:
        case LC32_OPENAL_OP_alSpeedOfSound: case LC32_OPENAL_OP_alDistanceModel: {
            ALenum parameter = opcode == LC32_OPENAL_OP_alDopplerFactor ? AL_DOPPLER_FACTOR :
                opcode == LC32_OPENAL_OP_alDopplerVelocity ? AL_DOPPLER_VELOCITY :
                opcode == LC32_OPENAL_OP_alSpeedOfSound ? AL_SPEED_OF_SOUND : AL_DISTANCE_MODEL;
            double value = parameter == AL_DISTANCE_MODEL ? double(w[0]) : WordToFloat(w[0]);
            if(parameter == AL_DISTANCE_MODEL) {
                if(value != AL_NONE && (value < AL_INVERSE_DISTANCE || value > AL_EXPONENT_DISTANCE_CLAMPED)) { c.fail(AL_INVALID_VALUE); break; }
            } else if(!std::isfinite(value) || value < 0 || (parameter != AL_DOPPLER_FACTOR && value == 0)) { c.fail(AL_INVALID_VALUE); break; }
            c.globals[parameter][0] = value;
            break;
        }
        default: c.fail(AL_INVALID_ENUM); break;
    }
    return true;
}
