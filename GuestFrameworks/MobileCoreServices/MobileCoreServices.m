// Public MobileCoreServices compatibility for legacy applications.
//
// Uniform type identifiers are stable, process-independent strings. Keep
// their values guest-native instead of loading the old LaunchServices/XPC
// dependency graph merely to obtain constant objects.

#import <MobileCoreServices/MobileCoreServices.h>

#define LC32_UT_STRING(name, value) \
    const CFStringRef name = CFSTR(value)

LC32_UT_STRING(kUTExportedTypeDeclarationsKey,
               "UTExportedTypeDeclarations");
LC32_UT_STRING(kUTImportedTypeDeclarationsKey,
               "UTImportedTypeDeclarations");
LC32_UT_STRING(kUTTypeIdentifierKey, "UTTypeIdentifier");
LC32_UT_STRING(kUTTypeTagSpecificationKey, "UTTypeTagSpecification");
LC32_UT_STRING(kUTTypeConformsToKey, "UTTypeConformsTo");
LC32_UT_STRING(kUTTypeDescriptionKey, "UTTypeDescription");
LC32_UT_STRING(kUTTypeIconFileKey, "UTTypeIconFile");
LC32_UT_STRING(kUTTypeReferenceURLKey, "UTTypeReferenceURL");
LC32_UT_STRING(kUTTypeVersionKey, "UTTypeVersion");

LC32_UT_STRING(kUTTagClassFilenameExtension,
               "public.filename-extension");
LC32_UT_STRING(kUTTagClassMIMEType, "public.mime-type");
LC32_UT_STRING(kUTTagClassNSPboardType, "com.apple.nspboard-type");
LC32_UT_STRING(kUTTagClassOSType, "com.apple.ostype");

LC32_UT_STRING(kUTTypeItem, "public.item");
LC32_UT_STRING(kUTTypeContent, "public.content");
LC32_UT_STRING(kUTTypeCompositeContent, "public.composite-content");
LC32_UT_STRING(kUTTypeMessage, "public.message");
LC32_UT_STRING(kUTTypeContact, "public.contact");
LC32_UT_STRING(kUTTypeArchive, "public.archive");
LC32_UT_STRING(kUTTypeDiskImage, "public.disk-image");
LC32_UT_STRING(kUTTypeData, "public.data");
LC32_UT_STRING(kUTTypeDirectory, "public.directory");
LC32_UT_STRING(kUTTypeResolvable, "com.apple.resolvable");
LC32_UT_STRING(kUTTypeSymLink, "public.symlink");
LC32_UT_STRING(kUTTypeExecutable, "public.executable");
LC32_UT_STRING(kUTTypeMountPoint, "com.apple.mount-point");
LC32_UT_STRING(kUTTypeAliasFile, "com.apple.alias-file");
LC32_UT_STRING(kUTTypeAliasRecord, "com.apple.alias-record");
LC32_UT_STRING(kUTTypeURLBookmarkData, "com.apple.bookmark");
LC32_UT_STRING(kUTTypeURL, "public.url");
LC32_UT_STRING(kUTTypeFileURL, "public.file-url");
LC32_UT_STRING(kUTTypeText, "public.text");
LC32_UT_STRING(kUTTypePlainText, "public.plain-text");
LC32_UT_STRING(kUTTypeUTF8PlainText, "public.utf8-plain-text");
LC32_UT_STRING(kUTTypeUTF16ExternalPlainText,
               "public.utf16-external-plain-text");
LC32_UT_STRING(kUTTypeUTF16PlainText, "public.utf16-plain-text");
LC32_UT_STRING(kUTTypeDelimitedText, "public.delimited-values-text");
LC32_UT_STRING(kUTTypeCommaSeparatedText,
               "public.comma-separated-values-text");
LC32_UT_STRING(kUTTypeTabSeparatedText,
               "public.tab-separated-values-text");
LC32_UT_STRING(kUTTypeUTF8TabSeparatedText,
               "public.utf8-tab-separated-values-text");
LC32_UT_STRING(kUTTypeRTF, "public.rtf");
LC32_UT_STRING(kUTTypeHTML, "public.html");
LC32_UT_STRING(kUTTypeXML, "public.xml");
LC32_UT_STRING(kUTTypeSourceCode, "public.source-code");
LC32_UT_STRING(kUTTypeAssemblyLanguageSource, "public.assembly-source");
LC32_UT_STRING(kUTTypeCSource, "public.c-source");
LC32_UT_STRING(kUTTypeObjectiveCSource, "public.objective-c-source");
LC32_UT_STRING(kUTTypeSwiftSource, "public.swift-source");
LC32_UT_STRING(kUTTypeCPlusPlusSource, "public.c-plus-plus-source");
LC32_UT_STRING(kUTTypeObjectiveCPlusPlusSource,
               "public.objective-c-plus-plus-source");
LC32_UT_STRING(kUTTypeCHeader, "public.c-header");
LC32_UT_STRING(kUTTypeCPlusPlusHeader, "public.c-plus-plus-header");
LC32_UT_STRING(kUTTypeJavaSource, "com.sun.java-source");
LC32_UT_STRING(kUTTypeScript, "public.script");
LC32_UT_STRING(kUTTypeAppleScript, "com.apple.applescript.text");
LC32_UT_STRING(kUTTypeOSAScript, "com.apple.applescript.script");
LC32_UT_STRING(kUTTypeOSAScriptBundle,
               "com.apple.applescript.script-bundle");
LC32_UT_STRING(kUTTypeJavaScript, "com.netscape.javascript-source");
LC32_UT_STRING(kUTTypeShellScript, "public.shell-script");
LC32_UT_STRING(kUTTypePerlScript, "public.perl-script");
LC32_UT_STRING(kUTTypePythonScript, "public.python-script");
LC32_UT_STRING(kUTTypeRubyScript, "public.ruby-script");
LC32_UT_STRING(kUTTypePHPScript, "public.php-script");
LC32_UT_STRING(kUTTypeJSON, "public.json");
LC32_UT_STRING(kUTTypePropertyList, "com.apple.property-list");
LC32_UT_STRING(kUTTypeXMLPropertyList, "com.apple.xml-property-list");
LC32_UT_STRING(kUTTypeBinaryPropertyList,
               "com.apple.binary-property-list");
LC32_UT_STRING(kUTTypePDF, "com.adobe.pdf");
LC32_UT_STRING(kUTTypeRTFD, "com.apple.rtfd");
LC32_UT_STRING(kUTTypeFlatRTFD, "com.apple.flat-rtfd");
LC32_UT_STRING(kUTTypeTXNTextAndMultimediaData,
               "com.apple.txn.text-multimedia-data");
LC32_UT_STRING(kUTTypeWebArchive, "com.apple.webarchive");
LC32_UT_STRING(kUTTypeImage, "public.image");
LC32_UT_STRING(kUTTypeJPEG, "public.jpeg");
LC32_UT_STRING(kUTTypeJPEG2000, "public.jpeg-2000");
LC32_UT_STRING(kUTTypeTIFF, "public.tiff");
LC32_UT_STRING(kUTTypePICT, "com.apple.pict");
LC32_UT_STRING(kUTTypeGIF, "com.compuserve.gif");
LC32_UT_STRING(kUTTypePNG, "public.png");
LC32_UT_STRING(kUTTypeQuickTimeImage, "com.apple.quicktime-image");
LC32_UT_STRING(kUTTypeAppleICNS, "com.apple.icns");
LC32_UT_STRING(kUTTypeBMP, "com.microsoft.bmp");
LC32_UT_STRING(kUTTypeICO, "com.microsoft.ico");
LC32_UT_STRING(kUTTypeRawImage, "public.camera-raw-image");
LC32_UT_STRING(kUTTypeScalableVectorGraphics, "public.svg-image");
LC32_UT_STRING(kUTTypeLivePhoto, "com.apple.live-photo");
LC32_UT_STRING(kUTTypeAudiovisualContent, "public.audiovisual-content");
LC32_UT_STRING(kUTTypeMovie, "public.movie");
LC32_UT_STRING(kUTTypeVideo, "public.video");
LC32_UT_STRING(kUTTypeAudio, "public.audio");
LC32_UT_STRING(kUTTypeQuickTimeMovie, "com.apple.quicktime-movie");
LC32_UT_STRING(kUTTypeMPEG, "public.mpeg");
LC32_UT_STRING(kUTTypeMPEG2Video, "public.mpeg-2-video");
LC32_UT_STRING(kUTTypeMPEG2TransportStream,
               "public.mpeg-2-transport-stream");
LC32_UT_STRING(kUTTypeMP3, "public.mp3");
LC32_UT_STRING(kUTTypeMPEG4, "public.mpeg-4");
LC32_UT_STRING(kUTTypeMPEG4Audio, "public.mpeg-4-audio");
LC32_UT_STRING(kUTTypeAppleProtectedMPEG4Audio,
               "com.apple.protected-mpeg-4-audio");
LC32_UT_STRING(kUTTypeAppleProtectedMPEG4Video,
               "com.apple.protected-mpeg-4-video");
LC32_UT_STRING(kUTTypeAVIMovie, "public.avi");
LC32_UT_STRING(kUTTypeAudioInterchangeFileFormat, "public.aiff-audio");
LC32_UT_STRING(kUTTypeWaveformAudio, "com.microsoft.waveform-audio");
LC32_UT_STRING(kUTTypeMIDIAudio, "public.midi-audio");
LC32_UT_STRING(kUTTypePlaylist, "public.playlist");
LC32_UT_STRING(kUTTypeM3UPlaylist, "public.m3u-playlist");
LC32_UT_STRING(kUTTypeFolder, "public.folder");
LC32_UT_STRING(kUTTypeVolume, "public.volume");
LC32_UT_STRING(kUTTypePackage, "com.apple.package");
LC32_UT_STRING(kUTTypeBundle, "com.apple.bundle");
LC32_UT_STRING(kUTTypePluginBundle, "com.apple.plugin");
LC32_UT_STRING(kUTTypeSpotlightImporter, "com.apple.metadata-importer");
LC32_UT_STRING(kUTTypeQuickLookGenerator,
               "com.apple.quicklook-generator");
LC32_UT_STRING(kUTTypeXPCService, "com.apple.xpc-service");
LC32_UT_STRING(kUTTypeFramework, "com.apple.framework");
LC32_UT_STRING(kUTTypeApplication, "com.apple.application");
LC32_UT_STRING(kUTTypeApplicationBundle, "com.apple.application-bundle");
LC32_UT_STRING(kUTTypeApplicationFile, "com.apple.application-file");
LC32_UT_STRING(kUTTypeUnixExecutable, "public.unix-executable");
LC32_UT_STRING(kUTTypeWindowsExecutable,
               "com.microsoft.windows-executable");
LC32_UT_STRING(kUTTypeJavaClass, "com.sun.java-class");
LC32_UT_STRING(kUTTypeJavaArchive, "com.sun.java-archive");
LC32_UT_STRING(kUTTypeSystemPreferencesPane,
               "com.apple.systempreference.prefpane");
LC32_UT_STRING(kUTTypeGNUZipArchive, "org.gnu.gnu-zip-archive");
LC32_UT_STRING(kUTTypeBzip2Archive, "public.bzip2-archive");
LC32_UT_STRING(kUTTypeZipArchive, "public.zip-archive");
LC32_UT_STRING(kUTTypeSpreadsheet, "public.spreadsheet");
LC32_UT_STRING(kUTTypePresentation, "public.presentation");
LC32_UT_STRING(kUTTypeDatabase, "public.database");
LC32_UT_STRING(kUTTypeVCard, "public.vcard");
LC32_UT_STRING(kUTTypeToDoItem, "public.to-do-item");
LC32_UT_STRING(kUTTypeCalendarEvent, "public.calendar-event");
LC32_UT_STRING(kUTTypeEmailMessage, "public.email-message");
LC32_UT_STRING(kUTTypeInternetLocation, "com.apple.internet-location");
LC32_UT_STRING(kUTTypeInkText, "com.apple.ink.inktext");
LC32_UT_STRING(kUTTypeFont, "public.font");
LC32_UT_STRING(kUTTypeBookmark, "public.bookmark");
LC32_UT_STRING(kUTType3DContent, "public.3d-content");
LC32_UT_STRING(kUTTypePKCS12, "com.rsa.pkcs-12");
LC32_UT_STRING(kUTTypeX509Certificate, "public.x509-certificate");
LC32_UT_STRING(kUTTypeElectronicPublication,
               "org.idpf.epub-container");
LC32_UT_STRING(kUTTypeLog, "public.log");

#undef LC32_UT_STRING

typedef struct {
    CFStringRef identifier;
    CFStringRef parent;
    CFStringRef filenameExtension;
    CFStringRef alternateFilenameExtension;
    CFStringRef mimeType;
    CFStringRef description;
} LC32UTTypeDeclaration;

#define LC32_UT_DECL(uti, parent, extension, alternate, mime, description) \
    { CFSTR(uti), parent, extension, alternate, mime, CFSTR(description) }
#define LC32_UT_PARENT(uti) CFSTR(uti)
#define LC32_UT_TAG(tag) CFSTR(tag)
#define LC32_UT_NO_TAG NULL

/* A compact declaration database covers the file types most often queried by
 * legacy applications. Unknown tags remain unsupported instead of inventing
 * unstable dynamic UTI strings. */
static const LC32UTTypeDeclaration LC32UTTypeDeclarations[] = {
    LC32_UT_DECL("public.item", NULL, NULL, NULL, NULL, "Item"),
    LC32_UT_DECL("public.content", LC32_UT_PARENT("public.item"), NULL, NULL,
        NULL, "Content"),
    LC32_UT_DECL("public.data", LC32_UT_PARENT("public.item"), NULL, NULL,
        NULL, "Data"),
    LC32_UT_DECL("public.text", LC32_UT_PARENT("public.content"), NULL, NULL,
        NULL, "Text"),
    LC32_UT_DECL("public.plain-text", LC32_UT_PARENT("public.text"),
        LC32_UT_TAG("txt"), LC32_UT_TAG("text"), LC32_UT_TAG("text/plain"),
        "Plain text"),
    LC32_UT_DECL("public.utf8-plain-text", LC32_UT_PARENT("public.plain-text"),
        NULL, NULL, NULL, "UTF-8 plain text"),
    LC32_UT_DECL("public.rtf", LC32_UT_PARENT("public.text"),
        LC32_UT_TAG("rtf"), NULL, LC32_UT_TAG("application/rtf"),
        "Rich Text Format"),
    LC32_UT_DECL("public.html", LC32_UT_PARENT("public.text"),
        LC32_UT_TAG("html"), LC32_UT_TAG("htm"), LC32_UT_TAG("text/html"),
        "HTML document"),
    LC32_UT_DECL("public.xml", LC32_UT_PARENT("public.text"),
        LC32_UT_TAG("xml"), NULL, LC32_UT_TAG("application/xml"),
        "XML document"),
    LC32_UT_DECL("public.json", LC32_UT_PARENT("public.text"),
        LC32_UT_TAG("json"), NULL, LC32_UT_TAG("application/json"),
        "JSON document"),
    LC32_UT_DECL("com.adobe.pdf", LC32_UT_PARENT("public.data"),
        LC32_UT_TAG("pdf"), NULL, LC32_UT_TAG("application/pdf"),
        "PDF document"),
    LC32_UT_DECL("public.image", LC32_UT_PARENT("public.content"), NULL, NULL,
        NULL, "Image"),
    LC32_UT_DECL("public.jpeg", LC32_UT_PARENT("public.image"),
        LC32_UT_TAG("jpg"), LC32_UT_TAG("jpeg"), LC32_UT_TAG("image/jpeg"),
        "JPEG image"),
    LC32_UT_DECL("public.png", LC32_UT_PARENT("public.image"),
        LC32_UT_TAG("png"), NULL, LC32_UT_TAG("image/png"), "PNG image"),
    LC32_UT_DECL("public.tiff", LC32_UT_PARENT("public.image"),
        LC32_UT_TAG("tif"), LC32_UT_TAG("tiff"), LC32_UT_TAG("image/tiff"),
        "TIFF image"),
    LC32_UT_DECL("com.compuserve.gif", LC32_UT_PARENT("public.image"),
        LC32_UT_TAG("gif"), NULL, LC32_UT_TAG("image/gif"), "GIF image"),
    LC32_UT_DECL("com.microsoft.bmp", LC32_UT_PARENT("public.image"),
        LC32_UT_TAG("bmp"), NULL, LC32_UT_TAG("image/bmp"), "Bitmap image"),
    LC32_UT_DECL("public.svg-image", LC32_UT_PARENT("public.image"),
        LC32_UT_TAG("svg"), NULL, LC32_UT_TAG("image/svg+xml"), "SVG image"),
    LC32_UT_DECL("public.audiovisual-content",
        LC32_UT_PARENT("public.content"), NULL, NULL, NULL,
        "Audiovisual content"),
    LC32_UT_DECL("public.movie", LC32_UT_PARENT("public.audiovisual-content"),
        NULL, NULL, NULL, "Movie"),
    LC32_UT_DECL("public.video", LC32_UT_PARENT("public.movie"), NULL, NULL,
        NULL, "Video"),
    LC32_UT_DECL("public.audio", LC32_UT_PARENT("public.audiovisual-content"),
        NULL, NULL, NULL, "Audio"),
    LC32_UT_DECL("com.apple.quicktime-movie", LC32_UT_PARENT("public.movie"),
        LC32_UT_TAG("mov"), NULL, LC32_UT_TAG("video/quicktime"),
        "QuickTime movie"),
    LC32_UT_DECL("public.mpeg", LC32_UT_PARENT("public.movie"),
        LC32_UT_TAG("mpg"), LC32_UT_TAG("mpeg"), LC32_UT_TAG("video/mpeg"),
        "MPEG movie"),
    LC32_UT_DECL("public.mpeg-4", LC32_UT_PARENT("public.movie"),
        LC32_UT_TAG("mp4"), NULL, LC32_UT_TAG("video/mp4"), "MPEG-4 movie"),
    LC32_UT_DECL("public.mp3", LC32_UT_PARENT("public.audio"),
        LC32_UT_TAG("mp3"), NULL, LC32_UT_TAG("audio/mpeg"), "MP3 audio"),
    LC32_UT_DECL("public.mpeg-4-audio", LC32_UT_PARENT("public.audio"),
        LC32_UT_TAG("m4a"), NULL, LC32_UT_TAG("audio/mp4"), "MPEG-4 audio"),
    LC32_UT_DECL("public.avi", LC32_UT_PARENT("public.movie"),
        LC32_UT_TAG("avi"), NULL, LC32_UT_TAG("video/x-msvideo"), "AVI movie"),
    LC32_UT_DECL("public.aiff-audio", LC32_UT_PARENT("public.audio"),
        LC32_UT_TAG("aiff"), LC32_UT_TAG("aif"), LC32_UT_TAG("audio/aiff"),
        "AIFF audio"),
    LC32_UT_DECL("com.microsoft.waveform-audio", LC32_UT_PARENT("public.audio"),
        LC32_UT_TAG("wav"), NULL, LC32_UT_TAG("audio/wav"), "Waveform audio"),
    LC32_UT_DECL("public.midi-audio", LC32_UT_PARENT("public.audio"),
        LC32_UT_TAG("midi"), LC32_UT_TAG("mid"), LC32_UT_TAG("audio/midi"),
        "MIDI audio"),
    LC32_UT_DECL("public.archive", LC32_UT_PARENT("public.data"), NULL, NULL,
        NULL, "Archive"),
    LC32_UT_DECL("org.gnu.gnu-zip-archive", LC32_UT_PARENT("public.archive"),
        LC32_UT_TAG("gz"), NULL, LC32_UT_TAG("application/gzip"),
        "Gzip archive"),
    LC32_UT_DECL("public.bzip2-archive", LC32_UT_PARENT("public.archive"),
        LC32_UT_TAG("bz2"), NULL, LC32_UT_TAG("application/x-bzip2"),
        "Bzip2 archive"),
    LC32_UT_DECL("public.zip-archive", LC32_UT_PARENT("public.archive"),
        LC32_UT_TAG("zip"), NULL, LC32_UT_TAG("application/zip"),
        "Zip archive"),
    LC32_UT_DECL("public.folder", LC32_UT_PARENT("public.directory"), NULL,
        NULL, NULL, "Folder"),
    LC32_UT_DECL("public.directory", LC32_UT_PARENT("public.item"), NULL,
        NULL, NULL, "Directory"),
    LC32_UT_DECL("com.apple.package", LC32_UT_PARENT("public.directory"),
        NULL, NULL, NULL, "Package"),
    LC32_UT_DECL("com.apple.bundle", LC32_UT_PARENT("com.apple.package"),
        NULL, NULL, NULL, "Bundle"),
    LC32_UT_DECL("com.apple.application-bundle",
        LC32_UT_PARENT("com.apple.bundle"), LC32_UT_TAG("app"), NULL,
        NULL, "Application"),
    LC32_UT_DECL("com.apple.framework", LC32_UT_PARENT("com.apple.bundle"),
        LC32_UT_TAG("framework"), NULL, NULL, "Framework"),
    LC32_UT_DECL("public.source-code", LC32_UT_PARENT("public.text"), NULL,
        NULL, NULL, "Source code"),
    LC32_UT_DECL("public.c-source", LC32_UT_PARENT("public.source-code"),
        LC32_UT_TAG("c"), NULL, LC32_UT_TAG("text/x-c"), "C source code"),
    LC32_UT_DECL("public.objective-c-source",
        LC32_UT_PARENT("public.source-code"), LC32_UT_TAG("m"), NULL,
        LC32_UT_TAG("text/x-objective-c"), "Objective-C source code"),
    LC32_UT_DECL("public.c-plus-plus-source",
        LC32_UT_PARENT("public.source-code"), LC32_UT_TAG("cpp"),
        LC32_UT_TAG("cc"), LC32_UT_TAG("text/x-c++src"), "C++ source code"),
    LC32_UT_DECL("public.c-header", LC32_UT_PARENT("public.source-code"),
        LC32_UT_TAG("h"), NULL, LC32_UT_TAG("text/x-chdr"), "C header"),
    LC32_UT_DECL("public.swift-source", LC32_UT_PARENT("public.source-code"),
        LC32_UT_TAG("swift"), NULL, LC32_UT_TAG("text/x-swift"),
        "Swift source code"),
    LC32_UT_DECL("com.sun.java-source", LC32_UT_PARENT("public.source-code"),
        LC32_UT_TAG("java"), NULL, LC32_UT_TAG("text/x-java-source"),
        "Java source code"),
    LC32_UT_DECL("public.vcard", LC32_UT_PARENT("public.text"),
        LC32_UT_TAG("vcf"), NULL, LC32_UT_TAG("text/vcard"), "vCard"),
    LC32_UT_DECL("public.calendar-event", LC32_UT_PARENT("public.text"),
        LC32_UT_TAG("ics"), NULL, LC32_UT_TAG("text/calendar"),
        "Calendar event"),
    LC32_UT_DECL("org.idpf.epub-container", LC32_UT_PARENT("public.archive"),
        LC32_UT_TAG("epub"), NULL, LC32_UT_TAG("application/epub+zip"),
        "EPUB document"),
    LC32_UT_DECL("com.rsa.pkcs-12", LC32_UT_PARENT("public.data"),
        LC32_UT_TAG("p12"), LC32_UT_TAG("pfx"),
        LC32_UT_TAG("application/x-pkcs12"), "PKCS #12 data"),
    LC32_UT_DECL("public.x509-certificate", LC32_UT_PARENT("public.data"),
        LC32_UT_TAG("cer"), LC32_UT_TAG("crt"),
        LC32_UT_TAG("application/x-x509-ca-cert"), "X.509 certificate"),
    LC32_UT_DECL("public.log", LC32_UT_PARENT("public.plain-text"),
        LC32_UT_TAG("log"), NULL, LC32_UT_TAG("text/plain"), "Log file"),
};

#undef LC32_UT_DECL
#undef LC32_UT_PARENT
#undef LC32_UT_TAG
#undef LC32_UT_NO_TAG

static CFIndex LC32UTTypeDeclarationCount(void) {
    return sizeof(LC32UTTypeDeclarations) / sizeof(LC32UTTypeDeclarations[0]);
}

static Boolean LC32UTStringsEqual(CFStringRef left, CFStringRef right) {
    if(!left || !right) return false;
    return CFStringCompare(left, right,
        kCFCompareCaseInsensitive) == kCFCompareEqualTo;
}

static const LC32UTTypeDeclaration *LC32UTFindDeclaration(
        CFStringRef identifier) {
    for(CFIndex index = 0; index < LC32UTTypeDeclarationCount(); index++) {
        if(LC32UTStringsEqual(
                LC32UTTypeDeclarations[index].identifier, identifier))
            return &LC32UTTypeDeclarations[index];
    }
    return NULL;
}

static Boolean LC32UTDeclarationHasTag(
        const LC32UTTypeDeclaration *declaration, CFStringRef tagClass,
        CFStringRef tag) {
    if(LC32UTStringsEqual(tagClass, kUTTagClassFilenameExtension)) {
        return LC32UTStringsEqual(tag, declaration->filenameExtension) ||
            LC32UTStringsEqual(tag, declaration->alternateFilenameExtension);
    }
    if(LC32UTStringsEqual(tagClass, kUTTagClassMIMEType))
        return LC32UTStringsEqual(tag, declaration->mimeType);
    return false;
}

Boolean UTTypeConformsTo(CFStringRef inUTI, CFStringRef inConformsToUTI) {
    if(!inUTI || !inConformsToUTI) return false;
    CFStringRef current = inUTI;
    for(CFIndex depth = 0; current && depth < 32; depth++) {
        if(LC32UTStringsEqual(current, inConformsToUTI)) return true;
        const LC32UTTypeDeclaration *declaration =
            LC32UTFindDeclaration(current);
        current = declaration ? declaration->parent : NULL;
    }
    return false;
}

CFStringRef UTTypeCreatePreferredIdentifierForTag(
        CFStringRef inTagClass, CFStringRef inTag,
        CFStringRef inConformingToUTI) {
    if(!inTagClass || !inTag) return NULL;
    for(CFIndex index = 0; index < LC32UTTypeDeclarationCount(); index++) {
        const LC32UTTypeDeclaration *declaration =
            &LC32UTTypeDeclarations[index];
        if(LC32UTDeclarationHasTag(declaration, inTagClass, inTag) &&
                (!inConformingToUTI || UTTypeConformsTo(
                    declaration->identifier, inConformingToUTI))) {
            return CFStringCreateCopy(
                kCFAllocatorDefault, declaration->identifier);
        }
    }
    return NULL;
}

CFArrayRef UTTypeCreateAllIdentifiersForTag(
        CFStringRef inTagClass, CFStringRef inTag,
        CFStringRef inConformingToUTI) {
    if(!inTagClass || !inTag) return NULL;
    const void *identifiers[64];
    CFIndex count = 0;
    for(CFIndex index = 0;
            index < LC32UTTypeDeclarationCount() && count < 64; index++) {
        const LC32UTTypeDeclaration *declaration =
            &LC32UTTypeDeclarations[index];
        if(LC32UTDeclarationHasTag(declaration, inTagClass, inTag) &&
                (!inConformingToUTI || UTTypeConformsTo(
                    declaration->identifier, inConformingToUTI))) {
            identifiers[count++] = declaration->identifier;
        }
    }
    return count ? CFArrayCreate(kCFAllocatorDefault, identifiers, count,
        &kCFTypeArrayCallBacks) : NULL;
}

CFStringRef UTTypeCopyPreferredTagWithClass(
        CFStringRef inUTI, CFStringRef inTagClass) {
    const LC32UTTypeDeclaration *declaration =
        LC32UTFindDeclaration(inUTI);
    if(!declaration || !inTagClass) return NULL;
    CFStringRef tag = NULL;
    if(LC32UTStringsEqual(inTagClass, kUTTagClassFilenameExtension))
        tag = declaration->filenameExtension;
    else if(LC32UTStringsEqual(inTagClass, kUTTagClassMIMEType))
        tag = declaration->mimeType;
    return tag ? CFStringCreateCopy(kCFAllocatorDefault, tag) : NULL;
}

CFArrayRef UTTypeCopyAllTagsWithClass(
        CFStringRef inUTI, CFStringRef inTagClass) {
    const LC32UTTypeDeclaration *declaration =
        LC32UTFindDeclaration(inUTI);
    if(!declaration || !inTagClass) return NULL;
    const void *tags[2];
    CFIndex count = 0;
    if(LC32UTStringsEqual(inTagClass, kUTTagClassFilenameExtension)) {
        if(declaration->filenameExtension)
            tags[count++] = declaration->filenameExtension;
        if(declaration->alternateFilenameExtension)
            tags[count++] = declaration->alternateFilenameExtension;
    } else if(LC32UTStringsEqual(inTagClass, kUTTagClassMIMEType) &&
            declaration->mimeType) {
        tags[count++] = declaration->mimeType;
    }
    return count ? CFArrayCreate(kCFAllocatorDefault, tags, count,
        &kCFTypeArrayCallBacks) : NULL;
}

CFStringRef UTTypeCopyDescription(CFStringRef inUTI) {
    const LC32UTTypeDeclaration *declaration =
        LC32UTFindDeclaration(inUTI);
    return declaration ? CFStringCreateCopy(
        kCFAllocatorDefault, declaration->description) : NULL;
}

Boolean UTTypeIsDeclared(CFStringRef inUTI) {
    return LC32UTFindDeclaration(inUTI) != NULL;
}

CFDictionaryRef UTTypeCopyDeclaration(CFStringRef inUTI) {
    const LC32UTTypeDeclaration *declaration =
        LC32UTFindDeclaration(inUTI);
    if(!declaration) return NULL;

    CFMutableDictionaryRef result = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    if(!result) return NULL;
    CFDictionarySetValue(result, kUTTypeIdentifierKey,
        declaration->identifier);
    CFDictionarySetValue(result, kUTTypeDescriptionKey,
        declaration->description);

    if(declaration->parent) {
        const void *parent = declaration->parent;
        CFArrayRef parents = CFArrayCreate(kCFAllocatorDefault,
            &parent, 1, &kCFTypeArrayCallBacks);
        if(parents) {
            CFDictionarySetValue(result, kUTTypeConformsToKey, parents);
            CFRelease(parents);
        }
    }

    CFMutableDictionaryRef tags = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    if(tags) {
        if(declaration->filenameExtension) {
            const void *extensions[2] = {
                declaration->filenameExtension,
                declaration->alternateFilenameExtension
            };
            CFIndex count = declaration->alternateFilenameExtension ? 2 : 1;
            CFArrayRef values = CFArrayCreate(kCFAllocatorDefault,
                extensions, count, &kCFTypeArrayCallBacks);
            if(values) {
                CFDictionarySetValue(tags,
                    kUTTagClassFilenameExtension, values);
                CFRelease(values);
            }
        }
        if(declaration->mimeType) {
            const void *mime = declaration->mimeType;
            CFArrayRef values = CFArrayCreate(kCFAllocatorDefault,
                &mime, 1, &kCFTypeArrayCallBacks);
            if(values) {
                CFDictionarySetValue(tags, kUTTagClassMIMEType, values);
                CFRelease(values);
            }
        }
        if(CFDictionaryGetCount(tags) != 0)
            CFDictionarySetValue(result, kUTTypeTagSpecificationKey, tags);
        CFRelease(tags);
    }
    return result;
}

CFURLRef UTTypeCopyDeclaringBundleURL(CFStringRef inUTI) {
    if(!LC32UTFindDeclaration(inUTI)) return NULL;
    return CFURLCreateWithString(kCFAllocatorDefault,
        CFSTR("file:///System/Library/CoreServices/CoreTypes.bundle/"), NULL);
}

Boolean UTTypeEqual(CFStringRef inUTI1, CFStringRef inUTI2) {
    return LC32UTStringsEqual(inUTI1, inUTI2);
}

Boolean UTTypeIsDynamic(CFStringRef inUTI) {
    if(!inUTI) return false;
    return CFStringHasPrefix(inUTI, CFSTR("dyn."));
}

void UTTypeShow(CFStringRef inUTI) {
    // This API is diagnostics-only.  Do not pull the private CFShow symbol
    // into an otherwise self-contained compatibility image.
    (void)inUTI;
}

void LC32MobileCoreServicesCompatibilityStub(void) {
}
