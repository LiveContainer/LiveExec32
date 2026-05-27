#import <OpenGLES/ES3/gl.h>
#import <LC32/LC32.h>
#if 0 // FIXME: has unhandled types
void glUniformMatrix2fv (GLint location, GLsizei count, GLboolean transpose, const GLfloat* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
void glDrawTexx(GLfixed x, GLfixed y, GLfixed z, GLfixed width, GLfixed height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
__asm__(".global _glDrawTexxOES\n _glDrawTexxOES = _glDrawTexx");
GLvoid glRenderbufferStorageMultisample(GLenum target, GLsizei samples, GLenum internalformat, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
__asm__(".global _glRenderbufferStorageMultisampleAPPLE\n _glRenderbufferStorageMultisampleAPPLE = _glRenderbufferStorageMultisample");
void glStencilFuncSeparate (GLenum face, GLenum func, GLint ref, GLuint mask) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniformMatrix4x2fv(GLuint program, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniformMatrix4x2fvEXT\n _glProgramUniformMatrix4x2fvEXT = _glProgramUniformMatrix4x2fv");
GLboolean glUnmapBuffer(GLenum target) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
__asm__(".global _glUnmapBufferOES\n _glUnmapBufferOES = _glUnmapBuffer");
#if 0 // FIXME: has unhandled types
void glDeleteTransformFeedbacks (GLsizei n, const GLuint* ids) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glDeleteFramebuffers(GLsizei n, const GLuint* framebuffers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
__asm__(".global _glDeleteFramebuffersOES\n _glDeleteFramebuffersOES = _glDeleteFramebuffers");
void glViewport (GLint x, GLint y, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
#if 0 // FIXME: has unhandled types
void glLoadMatrixf (const GLfloat *m) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type const GLfloat * */);
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glProgramBinary (GLuint program, GLenum binaryFormat, const GLvoid* binary, GLsizei length) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLvoid* */, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLvoid* */ 
  // No post-process for guest_arg3 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glInvalidateFramebuffer (GLenum target, GLsizei numAttachments, const GLenum* attachments) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLenum* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLenum* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLenum* */ 
  // return void
}
#endif
void glTexEnvx (GLenum target, GLenum pname, GLfixed param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glTexImage2D (GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLint border, GLenum format, GLenum type, const GLvoid* pixels) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
GLboolean glIsFramebuffer (GLuint framebuffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
#if 0 // FIXME: has unhandled types
void glCopyBufferSubData (GLenum readTarget, GLenum writeTarget, GLintptr readOffset, GLintptr writeOffset, GLsizeiptr size) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLintptr */ 
  /* declaration: unhandled type GLintptr */ 
  /* declaration: unhandled type GLsizeiptr */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLintptr */, /* parameterToBePassed: unhandled type GLintptr */, /* parameterToBePassed: unhandled type GLsizeiptr */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLintptr */ 
  /* postCall: unhandled type GLintptr */ 
  /* postCall: unhandled type GLsizeiptr */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glDrawTexf(GLfloat x, GLfloat y, GLfloat z, GLfloat width, GLfloat height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
__asm__(".global _glDrawTexfOES\n _glDrawTexfOES = _glDrawTexf");
#if 0 // FIXME: has unhandled types
void glDeleteSync (GLsync sync) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLsync */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLsync */);
  /* postCall: unhandled type GLsync */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetUniformfv (GLuint program, GLint location, GLfloat* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat* */ 
  // return void
}
#endif
void glFlush (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
GLvoid glGenerateMipmap(GLenum target) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
__asm__(".global _glGenerateMipmapOES\n _glGenerateMipmapOES = _glGenerateMipmap");
#if 0 // FIXME: has unhandled types
GLenum glClientWaitSync (GLsync sync, GLbitfield flags, GLuint64 timeout) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLsync */ 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLsync */, guest_arg1, guest_arg2);
  /* postCall: unhandled type GLsync */ 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  return (GLenum)host_ret;
}
#endif
void glResumeTransformFeedback (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
void glShadeModel (GLenum mode) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glBlitFramebuffer (GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1, GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1, GLbitfield mask, GLenum filter) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  uint64_t host_arg8 = (uint64_t)guest_arg8; 
  uint64_t host_arg9 = (uint64_t)guest_arg9; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7, guest_arg8, guest_arg9);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  // No post-process for guest_arg8 
  // No post-process for guest_arg9 
  // return void
}
void glBindBuffer (GLenum target, GLuint buffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
void glRenderbufferStorage (GLenum target, GLenum internalformat, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
void glPauseTransformFeedback (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
#if 0 // FIXME: has unhandled types
GLenum glClientWaitSync(GLsync sync, GLbitfield flags, GLuint64 timeout) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLsync */ 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLsync */, guest_arg1, guest_arg2);
  /* postCall: unhandled type GLsync */ 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  return (GLenum)host_ret;
}
#endif
__asm__(".global _glClientWaitSyncAPPLE\n _glClientWaitSyncAPPLE = _glClientWaitSync");
#if 0 // FIXME: has unhandled types
void glGetActiveUniformBlockiv (GLuint program, GLuint uniformBlockIndex, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
void glTexParameterx (GLenum target, GLenum pname, GLfixed param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
GLenum glCheckFramebufferStatus (GLenum target) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLenum)host_ret;
}
void glBlendEquationSeparate (GLenum modeRGB, GLenum modeAlpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
void glDeleteBuffers (GLsizei n, const GLuint* buffers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform4f(GLuint program, GLint location, GLfloat x, GLfloat y, GLfloat z, GLfloat w) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform4fEXT\n _glProgramUniform4fEXT = _glProgramUniform4f");
#if 0 // FIXME: has unhandled types
void glUniform3fv (GLint location, GLsizei count, const GLfloat* v) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
void glTexStorage3D (GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height, GLsizei depth) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // return void
}
#if 0 // FIXME: has unhandled types
int glGetUniformLocation (GLuint program, const GLchar* name) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLchar* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLchar* */ 
  /* returnLine: unhandled type int */
}
#endif
void glBlendFunc (GLenum sfactor, GLenum dfactor) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
GLboolean glUnmapBuffer (GLenum target) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
void glBindSampler (GLuint unit, GLuint sampler) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
void glHint (GLenum target, GLenum mode) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
void glCopyTexSubImage3D (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLint x, GLint y, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  uint64_t host_arg8 = (uint64_t)guest_arg8; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7, guest_arg8);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  // No post-process for guest_arg8 
  // return void
}
#if 0 // FIXME: has unhandled types
void glVertexAttribI4iv (GLuint index, const GLint* v) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform2fv(GLuint program, GLint location, GLsizei count, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform2fvEXT\n _glProgramUniform2fvEXT = _glProgramUniform2fv");
GLvoid glUseProgramStages(GLuint pipeline, GLbitfield stages, GLuint program) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
__asm__(".global _glUseProgramStagesEXT\n _glUseProgramStagesEXT = _glUseProgramStages");
#if 0 // FIXME: has unhandled types
void glGenFramebuffers (GLsizei n, GLuint* framebuffers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glShaderBinary (GLsizei n, const GLuint* shaders, GLenum binaryformat, const GLvoid* binary, GLsizei length) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */, guest_arg2, /* parameterToBePassed: unhandled type const GLvoid* */, guest_arg4);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLvoid* */ 
  // No post-process for guest_arg4 
  // return void
}
#endif
GLvoid glProgramUniform1ui(GLuint program, GLint location, GLuint x) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
__asm__(".global _glProgramUniform1uiEXT\n _glProgramUniform1uiEXT = _glProgramUniform1ui");
#if 0 // FIXME: has unhandled types
void glMultiTexCoord4f (GLenum target, GLfloat s, GLfloat t, GLfloat r, GLfloat q) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetShaderSource (GLuint shader, GLsizei bufsize, GLsizei* length, GLchar* source) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLchar* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLchar* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetFloatv (GLenum pname, GLfloat* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glVertexAttrib1fv (GLuint indx, const GLfloat* values) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glFlushMappedBufferRange(GLenum target, GLintptr offset, GLsizeiptr length) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLintptr */ 
  /* declaration: unhandled type GLsizeiptr */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLintptr */, /* parameterToBePassed: unhandled type GLsizeiptr */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLintptr */ 
  /* postCall: unhandled type GLsizeiptr */ 
  // return void
}
#endif
__asm__(".global _glFlushMappedBufferRangeEXT\n _glFlushMappedBufferRangeEXT = _glFlushMappedBufferRange");
void glDepthRangex (GLclampx zNear, GLclampx zFar) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
void glLineWidth (GLfloat width) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
void glStencilMask (GLuint mask) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glUniform3i (GLint location, GLint x, GLint y, GLint z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
void glFogx (GLenum pname, GLfixed param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetFramebufferAttachmentParameteriv (GLenum target, GLenum attachment, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glFogf (GLenum pname, GLfloat param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glTexSubImage3D (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLsizei width, GLsizei height, GLsizei depth, GLenum format, GLenum type, const GLvoid* pixels) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  uint64_t host_arg8 = (uint64_t)guest_arg8; 
  uint64_t host_arg9 = (uint64_t)guest_arg9; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7, guest_arg8, guest_arg9, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  // No post-process for guest_arg8 
  // No post-process for guest_arg9 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
void glRotatex (GLfixed angle, GLfixed x, GLfixed y, GLfixed z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniformMatrix4x3fv(GLuint program, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniformMatrix4x3fvEXT\n _glProgramUniformMatrix4x3fvEXT = _glProgramUniformMatrix4x3fv");
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform3uiv(GLuint program, GLint location, GLsizei count, const GLuint *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLuint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLuint * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform3uivEXT\n _glProgramUniform3uivEXT = _glProgramUniform3uiv");
#if 0 // FIXME: has unhandled types
void glUniformMatrix3x4fv (GLint location, GLsizei count, GLboolean transpose, const GLfloat* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
void glValidateProgram (GLuint program) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
GLboolean glIsShader (GLuint shader) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
GLvoid glFramebufferRenderbuffer(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
__asm__(".global _glFramebufferRenderbufferOES\n _glFramebufferRenderbufferOES = _glFramebufferRenderbuffer");
GLvoid glActiveShaderProgram(GLuint pipeline, GLuint program) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
__asm__(".global _glActiveShaderProgramEXT\n _glActiveShaderProgramEXT = _glActiveShaderProgram");
void glClearColorx (GLclampx red, GLclampx green, GLclampx blue, GLclampx alpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGenBuffers (GLsizei n, GLuint* buffers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glPointParameterfv (GLenum pname, const GLfloat *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glBufferSubData (GLenum target, GLintptr offset, GLsizeiptr size, const GLvoid* data) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLintptr */ 
  /* declaration: unhandled type GLsizeiptr */ 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLintptr */, /* parameterToBePassed: unhandled type GLsizeiptr */, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLintptr */ 
  /* postCall: unhandled type GLsizeiptr */ 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glBufferData (GLenum target, GLsizeiptr size, const GLvoid* data, GLenum usage) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLsizeiptr */ 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLsizeiptr */, /* parameterToBePassed: unhandled type const GLvoid* */, guest_arg3);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLsizeiptr */ 
  /* postCall: unhandled type const GLvoid* */ 
  // No post-process for guest_arg3 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniform3f (GLint location, GLfloat x, GLfloat y, GLfloat z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glDeleteVertexArrays (GLsizei n, const GLuint* arrays) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
GLboolean glIsVertexArray (GLuint array) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform1iv(GLuint program, GLint location, GLsizei count, const GLint *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLint * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform1ivEXT\n _glProgramUniform1ivEXT = _glProgramUniform1iv");
#if 0 // FIXME: has unhandled types
void glVertexAttrib4f (GLuint indx, GLfloat x, GLfloat y, GLfloat z, GLfloat w) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniform1iv (GLint location, GLsizei count, const GLint* v) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLsync glFenceSync(GLenum condition, GLbitfield flags) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* returnLine: unhandled type GLsync */
}
#endif
__asm__(".global _glFenceSyncAPPLE\n _glFenceSyncAPPLE = _glFenceSync");
GLboolean glIsProgram (GLuint program) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
void glScalex (GLfixed x, GLfixed y, GLfixed z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetLightxv (GLenum light, GLenum pname, GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfixed * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfixed * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetAttachedShaders (GLuint program, GLsizei maxcount, GLsizei* count, GLuint* shaders) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
void glEnableVertexAttribArray (GLuint index) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glLoadIdentity (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
void glVertexAttribDivisor (GLuint index, GLuint divisor) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetSamplerParameterfv (GLuint sampler, GLenum pname, GLfloat* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat* */ 
  // return void
}
#endif
void glPushMatrix (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
void glFramebufferRenderbuffer (GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
void glDisableVertexAttribArray (GLuint index) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid * glMapBuffer(GLenum target, GLenum access) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* returnLine: unhandled type GLvoid * */
}
#endif
__asm__(".global _glMapBufferOES\n _glMapBufferOES = _glMapBuffer");
#if 0 // FIXME: has unhandled types
void glUniformMatrix2x4fv (GLint location, GLsizei count, GLboolean transpose, const GLfloat* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
void glEndTransformFeedback (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetLightfv (GLenum light, GLenum pname, GLfloat *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glLightModelfv (GLenum pname, const GLfloat *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
GLboolean glIsQuery(GLuint id) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
__asm__(".global _glIsQueryEXT\n _glIsQueryEXT = _glIsQuery");
#if 0 // FIXME: has unhandled types
GLvoid* glMapBufferRange (GLenum target, GLintptr offset, GLsizeiptr length, GLbitfield access) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLintptr */ 
  /* declaration: unhandled type GLsizeiptr */ 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLintptr */, /* parameterToBePassed: unhandled type GLsizeiptr */, guest_arg3);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLintptr */ 
  /* postCall: unhandled type GLsizeiptr */ 
  // No post-process for guest_arg3 
  /* returnLine: unhandled type GLvoid* */
}
#endif
#if 0 // FIXME: has unhandled types
void glDrawElementsInstanced (GLenum mode, GLsizei count, GLenum type, const GLvoid* indices, GLsizei instancecount) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLvoid* */, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLvoid* */ 
  // No post-process for guest_arg4 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glPointSizePointer(GLenum type, GLsizei stride, const GLvoid *pointer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLvoid * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLvoid * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLvoid * */ 
  // return void
}
#endif
__asm__(".global _glPointSizePointerOES\n _glPointSizePointerOES = _glPointSizePointer");
GLvoid glBindFramebuffer(GLenum target, GLuint framebuffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
__asm__(".global _glBindFramebufferOES\n _glBindFramebufferOES = _glBindFramebuffer");
#if 0 // FIXME: has unhandled types
void glUniform3iv (GLint location, GLsizei count, const GLint* v) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLint* */ 
  // return void
}
#endif
void glDeleteShader (GLuint shader) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetQueryObjectuiv (GLuint id, GLenum pname, GLuint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
void glEndQuery (GLenum target) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glTexParameteriv (GLenum target, GLenum pname, const GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniformMatrix2x3fv(GLuint program, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniformMatrix2x3fvEXT\n _glProgramUniformMatrix2x3fvEXT = _glProgramUniformMatrix2x3fv");
void glStencilOpSeparate (GLenum face, GLenum fail, GLenum zfail, GLenum zpass) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
#if 0 // FIXME: has unhandled types
void glLightf (GLenum light, GLenum pname, GLfloat param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
void glDeleteProgram (GLuint program) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glClear (GLbitfield mask) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniformMatrix3fv(GLuint program, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniformMatrix3fvEXT\n _glProgramUniformMatrix3fvEXT = _glProgramUniformMatrix3fv");
#if 0 // FIXME: has unhandled types
void glGenQueries (GLsizei n, GLuint* ids) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glDrawTexiv(const GLint *coords) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type const GLint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type const GLint * */);
  /* postCall: unhandled type const GLint * */ 
  // return void
}
#endif
__asm__(".global _glDrawTexivOES\n _glDrawTexivOES = _glDrawTexiv");
#if 0 // FIXME: has unhandled types
void glGetActiveAttrib (GLuint program, GLuint index, GLsizei bufsize, GLsizei* length, GLint* size, GLenum* type, GLchar* name) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLint* */ 
  /* declaration: unhandled type GLenum* */ 
  /* declaration: unhandled type GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLint* */, /* parameterToBePassed: unhandled type GLenum* */, /* parameterToBePassed: unhandled type GLchar* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLint* */ 
  /* postCall: unhandled type GLenum* */ 
  /* postCall: unhandled type GLchar* */ 
  // return void
}
#endif
void glColor4ub (GLubyte red, GLubyte green, GLubyte blue, GLubyte alpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glInsertEventMarker(GLsizei length, const GLchar *marker) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLchar * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLchar * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLchar * */ 
  // return void
}
#endif
__asm__(".global _glInsertEventMarkerEXT\n _glInsertEventMarkerEXT = _glInsertEventMarker");
#if 0 // FIXME: has unhandled types
void glTexEnvfv (GLenum target, GLenum pname, const GLfloat *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetProgramBinary (GLuint program, GLsizei bufSize, GLsizei* length, GLenum* binaryFormat, GLvoid* binary) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLenum* */ 
  /* declaration: unhandled type GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLenum* */, /* parameterToBePassed: unhandled type GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLenum* */ 
  /* postCall: unhandled type GLvoid* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glGetQueryiv(GLenum target, GLenum pname, GLint *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint * */ 
  // return void
}
#endif
__asm__(".global _glGetQueryivEXT\n _glGetQueryivEXT = _glGetQueryiv");
#if 0 // FIXME: has unhandled types
void glTexEnviv (GLenum target, GLenum pname, const GLint *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLint * */ 
  // return void
}
#endif
GLvoid glCopyTextureLevels(GLuint destinationTexture, GLuint sourceTexture, GLint sourceBaseLevel, GLsizei sourceLevelCount) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
__asm__(".global _glCopyTextureLevelsAPPLE\n _glCopyTextureLevelsAPPLE = _glCopyTextureLevels");
#if 0 // FIXME: has unhandled types
void glNormal3f (GLfloat nx, GLfloat ny, GLfloat nz) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glDeleteVertexArrays(GLsizei n, const GLuint *arrays) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint * */ 
  // return void
}
#endif
__asm__(".global _glDeleteVertexArraysOES\n _glDeleteVertexArraysOES = _glDeleteVertexArrays");
void glLightModelx (GLenum pname, GLfixed param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
void glClearBufferfi (GLenum buffer, GLint drawbuffer, GLfloat depth, GLint stencil) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat */, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat */ 
  // No post-process for guest_arg3 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glVertexAttrib2fv (GLuint indx, const GLfloat* values) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glDeleteSync(GLsync sync) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLsync */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLsync */);
  /* postCall: unhandled type GLsync */ 
  // return void
}
#endif
__asm__(".global _glDeleteSyncAPPLE\n _glDeleteSyncAPPLE = _glDeleteSync");
#if 0 // FIXME: has unhandled types
void glVertexPointer (GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLvoid * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLvoid * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLvoid * */ 
  // return void
}
#endif
void glDisable (GLenum cap) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glCompileShader (GLuint shader) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glGenProgramPipelines(GLsizei n, GLuint *pipelines) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint * */ 
  // return void
}
#endif
__asm__(".global _glGenProgramPipelinesEXT\n _glGenProgramPipelinesEXT = _glGenProgramPipelines");
void glDrawTexs(GLshort x, GLshort y, GLshort z, GLshort width, GLshort height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
__asm__(".global _glDrawTexsOES\n _glDrawTexsOES = _glDrawTexs");
#if 0 // FIXME: has unhandled types
void glGetInteger64v (GLenum pname, GLint64* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLint64* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLint64* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLint64* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glTexEnvxv (GLenum target, GLenum pname, const GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfixed * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
void glCullFace (GLenum mode) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glNormal3x (GLfixed nx, GLfixed ny, GLfixed nz) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glBlendColor (GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
void glFramebufferTexture2D (GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
GLvoid glProgramUniform1i(GLuint program, GLint location, GLint x) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
__asm__(".global _glProgramUniform1iEXT\n _glProgramUniform1iEXT = _glProgramUniform1i");
#if 0 // FIXME: has unhandled types
void glClearDepthf (GLclampf depth) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLclampf */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLclampf */);
  /* postCall: unhandled type GLclampf */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetShaderPrecisionFormat (GLenum shadertype, GLenum precisiontype, GLint* range, GLint* precision) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glDiscardFramebuffer(GLenum target, GLsizei numAttachments, const GLenum *attachments) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLenum * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLenum * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLenum * */ 
  // return void
}
#endif
__asm__(".global _glDiscardFramebufferEXT\n _glDiscardFramebufferEXT = _glDiscardFramebuffer");
GLvoid glProgramUniform4ui(GLuint program, GLint location, GLuint x, GLuint y, GLuint z, GLuint w) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // return void
}
__asm__(".global _glProgramUniform4uiEXT\n _glProgramUniform4uiEXT = _glProgramUniform4ui");
GLenum glGetError (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  return (GLenum)host_ret;
}
#if 0 // FIXME: has unhandled types
void glGetVertexAttribfv (GLuint index, GLenum pname, GLfloat* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLboolean glIsSync(GLsync sync) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLsync */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLsync */);
  /* postCall: unhandled type GLsync */ 
  return (GLboolean)host_ret;
}
#endif
__asm__(".global _glIsSyncAPPLE\n _glIsSyncAPPLE = _glIsSync");
#if 0 // FIXME: has unhandled types
GLvoid glGenFramebuffers(GLsizei n, GLuint* framebuffers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
__asm__(".global _glGenFramebuffersOES\n _glGenFramebuffersOES = _glGenFramebuffers");
#if 0 // FIXME: has unhandled types
void glGetUniformIndices (GLuint program, GLsizei uniformCount, const GLchar* const *uniformNames, GLuint* uniformIndices) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLchar* const * */ 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLchar* const * */, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLchar* const * */ 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
void glEnable (GLenum cap) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
GLboolean glIsRenderbuffer (GLuint renderbuffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
void glPointSizex (GLfixed size) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glFlushMappedBufferRange (GLenum target, GLintptr offset, GLsizeiptr length) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLintptr */ 
  /* declaration: unhandled type GLsizeiptr */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLintptr */, /* parameterToBePassed: unhandled type GLsizeiptr */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLintptr */ 
  /* postCall: unhandled type GLsizeiptr */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniformMatrix3fv (GLint location, GLsizei count, GLboolean transpose, const GLfloat* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
void glBindVertexArray (GLuint array) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetBufferParameteriv (GLenum target, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetSynciv(GLsync sync, GLenum pname, GLsizei bufSize, GLsizei *length, GLint *values) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLsync */ 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLsizei * */ 
  /* declaration: unhandled type GLint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLsync */, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLsizei * */, /* parameterToBePassed: unhandled type GLint * */);
  /* postCall: unhandled type GLsync */ 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLsizei * */ 
  /* postCall: unhandled type GLint * */ 
  // return void
}
#endif
__asm__(".global _glGetSyncivAPPLE\n _glGetSyncivAPPLE = _glGetSynciv");
#if 0 // FIXME: has unhandled types
void glTexCoordPointer (GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLvoid * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLvoid * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLvoid * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glOrthof (GLfloat left, GLfloat right, GLfloat bottom, GLfloat top, GLfloat zNear, GLfloat zFar) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetActiveUniformBlockName (GLuint program, GLuint uniformBlockIndex, GLsizei bufSize, GLsizei* length, GLchar* uniformBlockName) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLchar* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLchar* */ 
  // return void
}
#endif
void glUniformBlockBinding (GLuint program, GLuint uniformBlockIndex, GLuint uniformBlockBinding) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glFrustumf (GLfloat left, GLfloat right, GLfloat bottom, GLfloat top, GLfloat zNear, GLfloat zFar) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glDrawElements (GLenum mode, GLsizei count, GLenum type, const GLvoid* indices) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
void glBeginTransformFeedback (GLenum primitiveMode) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform1fv(GLuint program, GLint location, GLsizei count, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform1fvEXT\n _glProgramUniform1fvEXT = _glProgramUniform1fv");
void glAttachShader (GLuint program, GLuint shader) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniformMatrix2x4fv(GLuint program, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniformMatrix2x4fvEXT\n _glProgramUniformMatrix2x4fvEXT = _glProgramUniformMatrix2x4fv");
#if 0 // FIXME: has unhandled types
void glGetFixedv (GLenum pname, GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfixed * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfixed * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetSamplerParameteriv (GLuint sampler, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
void glRenderbufferStorageMultisample (GLenum target, GLsizei samples, GLenum internalformat, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
void glDepthFunc (GLenum func) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glVertexAttribI4i (GLuint index, GLint x, GLint y, GLint z, GLint w) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetIntegerv (GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
void glUniform2ui (GLint location, GLuint v0, GLuint v1) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glTexSubImage2D (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLenum type, const GLvoid* pixels) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glGetRenderbufferParameteriv(GLenum target, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
__asm__(".global _glGetRenderbufferParameterivOES\n _glGetRenderbufferParameterivOES = _glGetRenderbufferParameteriv");
void glCopyTexSubImage2D (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  // return void
}
GLvoid glPopGroupMarker(void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
__asm__(".global _glPopGroupMarkerEXT\n _glPopGroupMarkerEXT = _glPopGroupMarker");
#if 0 // FIXME: has unhandled types
void glTranslatef (GLfloat x, GLfloat y, GLfloat z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetShaderiv (GLuint shader, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform4iv(GLuint program, GLint location, GLsizei count, const GLint *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLint * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform4ivEXT\n _glProgramUniform4ivEXT = _glProgramUniform4iv");
void glFrustumx (GLfixed left, GLfixed right, GLfixed bottom, GLfixed top, GLfixed zNear, GLfixed zFar) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetTexParameterxv (GLenum target, GLenum pname, GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfixed * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfixed * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glMultMatrixx (const GLfixed *m) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type const GLfixed * */);
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
GLvoid glProgramUniform2i(GLuint program, GLint location, GLint x, GLint y) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
__asm__(".global _glProgramUniform2iEXT\n _glProgramUniform2iEXT = _glProgramUniform2i");
#if 0 // FIXME: has unhandled types
GLvoid glDeleteQueries(GLsizei n, const GLuint *ids) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint * */ 
  // return void
}
#endif
__asm__(".global _glDeleteQueriesEXT\n _glDeleteQueriesEXT = _glDeleteQueries");
#if 0 // FIXME: has unhandled types
GLvoid glGenQueries(GLsizei n, GLuint *ids) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint * */ 
  // return void
}
#endif
__asm__(".global _glGenQueriesEXT\n _glGenQueriesEXT = _glGenQueries");
#if 0 // FIXME: has unhandled types
void glMatrixIndexPointer(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLvoid * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLvoid * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLvoid * */ 
  // return void
}
#endif
__asm__(".global _glMatrixIndexPointerOES\n _glMatrixIndexPointerOES = _glMatrixIndexPointer");
void glStencilMaskSeparate (GLenum face, GLuint mask) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
void glVertexAttrib3f (GLuint indx, GLfloat x, GLfloat y, GLfloat z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
void glPopMatrix (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
#if 0 // FIXME: has unhandled types
void glTexImage3D (GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height, GLsizei depth, GLint border, GLenum format, GLenum type, const GLvoid* pixels) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  uint64_t host_arg8 = (uint64_t)guest_arg8; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7, guest_arg8, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  // No post-process for guest_arg8 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
int glGetAttribLocation (GLuint program, const GLchar* name) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLchar* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLchar* */ 
  /* returnLine: unhandled type int */
}
#endif
GLboolean glIsFramebuffer(GLuint framebuffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
__asm__(".global _glIsFramebufferOES\n _glIsFramebufferOES = _glIsFramebuffer");
#if 0 // FIXME: has unhandled types
void glTransformFeedbackVaryings (GLuint program, GLsizei count, const GLchar* const *varyings, GLenum bufferMode) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLchar* const * */ 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLchar* const * */, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLchar* const * */ 
  // No post-process for guest_arg3 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glVertexAttrib3fv (GLuint indx, const GLfloat* values) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
GLboolean glIsTransformFeedback (GLuint id) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
void glUniform4ui (GLint location, GLuint v0, GLuint v1, GLuint v2, GLuint v3) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
void glLightx (GLenum light, GLenum pname, GLfixed param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glCompressedTexImage2D (GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLint border, GLsizei imageSize, const GLvoid* data) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetTexParameterfv (GLenum target, GLenum pname, GLfloat* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetBufferParameteri64v (GLenum target, GLenum pname, GLint64* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint64* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint64* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint64* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glAlphaFunc (GLenum func, GLclampf ref) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLclampf */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLclampf */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLclampf */ 
  // return void
}
#endif
GLvoid glBindRenderbuffer(GLenum target, GLuint renderbuffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
__asm__(".global _glBindRenderbufferOES\n _glBindRenderbufferOES = _glBindRenderbuffer");
#if 0 // FIXME: has unhandled types
void glBindBufferRange (GLenum target, GLuint index, GLuint buffer, GLintptr offset, GLsizeiptr size) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLintptr */ 
  /* declaration: unhandled type GLsizeiptr */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLintptr */, /* parameterToBePassed: unhandled type GLsizeiptr */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLintptr */ 
  /* postCall: unhandled type GLsizeiptr */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glVertexAttribIPointer (GLuint index, GLint size, GLenum type, GLsizei stride, const GLvoid* pointer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniformMatrix4x2fv (GLint location, GLsizei count, GLboolean transpose, const GLfloat* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
void glDepthMask (GLboolean flag) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glSamplerParameteri (GLuint sampler, GLenum pname, GLint param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glNormalPointer (GLenum type, GLsizei stride, const GLvoid *pointer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLvoid * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLvoid * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLvoid * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetInternalformativ (GLenum target, GLenum internalformat, GLenum pname, GLsizei bufSize, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glPointParameterxv (GLenum pname, const GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfixed * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
GLvoid glProgramUniform3i(GLuint program, GLint location, GLint x, GLint y, GLint z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
__asm__(".global _glProgramUniform3iEXT\n _glProgramUniform3iEXT = _glProgramUniform3i");
#if 0 // FIXME: has unhandled types
void glGetVertexAttribiv (GLuint index, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform2uiv(GLuint program, GLint location, GLsizei count, const GLuint *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLuint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLuint * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform2uivEXT\n _glProgramUniform2uivEXT = _glProgramUniform2uiv");
GLvoid glRenderbufferStorage(GLenum target, GLenum internalformat, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
__asm__(".global _glRenderbufferStorageOES\n _glRenderbufferStorageOES = _glRenderbufferStorage");
#if 0 // FIXME: has unhandled types
void glLoadMatrixx (const GLfixed *m) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type const GLfixed * */);
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glClipPlanef (GLenum plane, const GLfloat *equation) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetTransformFeedbackVarying (GLuint program, GLuint index, GLsizei bufSize, GLsizei* length, GLsizei* size, GLenum* type, GLchar* name) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLenum* */ 
  /* declaration: unhandled type GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLenum* */, /* parameterToBePassed: unhandled type GLchar* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLenum* */ 
  /* postCall: unhandled type GLchar* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glSamplerParameterfv (GLuint sampler, GLenum pname, const GLfloat* param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLboolean glIsSync (GLsync sync) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLsync */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLsync */);
  /* postCall: unhandled type GLsync */ 
  return (GLboolean)host_ret;
}
#endif
#if 0 // FIXME: has unhandled types
const GLubyte* glGetStringi (GLenum name, GLuint index) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* returnLine: unhandled type const GLubyte* */
}
#endif
#if 0 // FIXME: has unhandled types
void glGenTextures (GLsizei n, GLuint* textures) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
void glPixelStorei (GLenum pname, GLint param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniformMatrix3x2fv(GLuint program, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniformMatrix3x2fvEXT\n _glProgramUniformMatrix3x2fvEXT = _glProgramUniformMatrix3x2fv");
void glPointParameterx (GLenum pname, GLfixed param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
GLvoid glBindVertexArray(GLuint array) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
__asm__(".global _glBindVertexArrayOES\n _glBindVertexArrayOES = _glBindVertexArray");
void glLineWidthx (GLfixed width) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
GLvoid glProgramParameteri(GLuint program, GLenum pname, GLint value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
__asm__(".global _glProgramParameteriEXT\n _glProgramParameteriEXT = _glProgramParameteri");
#if 0 // FIXME: has unhandled types
void glPolygonOffset (GLfloat factor, GLfloat units) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glSamplerParameteriv (GLuint sampler, GLenum pname, const GLint* param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGenRenderbuffers (GLsizei n, GLuint* renderbuffers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
GLuint glCreateProgram (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  return (GLuint)host_ret;
}
#if 0 // FIXME: has unhandled types
GLvoid glLabelObject(GLenum type, GLuint object, GLsizei length, const GLchar *label) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLchar * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLchar * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLchar * */ 
  // return void
}
#endif
__asm__(".global _glLabelObjectEXT\n _glLabelObjectEXT = _glLabelObject");
#if 0 // FIXME: has unhandled types
GLvoid glDrawElementsInstanced(GLenum mode, GLsizei count, GLenum type, const GLvoid *indices, GLsizei instanceCount) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLvoid * */ 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLvoid * */, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLvoid * */ 
  // No post-process for guest_arg4 
  // return void
}
#endif
__asm__(".global _glDrawElementsInstancedEXT\n _glDrawElementsInstancedEXT = _glDrawElementsInstanced");
#if 0 // FIXME: has unhandled types
void glGetBooleanv (GLenum pname, GLboolean* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLboolean* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLboolean* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLboolean* */ 
  // return void
}
#endif
void glCurrentPaletteMatrix(GLuint matrixpaletteindex) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
__asm__(".global _glCurrentPaletteMatrixOES\n _glCurrentPaletteMatrixOES = _glCurrentPaletteMatrix");
#if 0 // FIXME: has unhandled types
void glGenTransformFeedbacks (GLsizei n, GLuint* ids) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniformMatrix3x2fv (GLint location, GLsizei count, GLboolean transpose, const GLfloat* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniform2fv (GLint location, GLsizei count, const GLfloat* v) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glGenRenderbuffers(GLsizei n, GLuint* renderbuffers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
__asm__(".global _glGenRenderbuffersOES\n _glGenRenderbuffersOES = _glGenRenderbuffers");
void glUniform2i (GLint location, GLint x, GLint y) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
void glMaterialx (GLenum face, GLenum pname, GLfixed param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
void glOrthox (GLfixed left, GLfixed right, GLfixed bottom, GLfixed top, GLfixed zNear, GLfixed zFar) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // return void
}
void glBeginQuery (GLenum target, GLuint id) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
GLvoid glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
__asm__(".global _glFramebufferTexture2DOES\n _glFramebufferTexture2DOES = _glFramebufferTexture2D");
#if 0 // FIXME: has unhandled types
void glInvalidateSubFramebuffer (GLenum target, GLsizei numAttachments, const GLenum* attachments, GLint x, GLint y, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLenum* */ 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLenum* */, guest_arg3, guest_arg4, guest_arg5, guest_arg6);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLenum* */ 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // return void
}
#endif
GLvoid glProgramUniform4i(GLuint program, GLint location, GLint x, GLint y, GLint z, GLint w) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // return void
}
__asm__(".global _glProgramUniform4iEXT\n _glProgramUniform4iEXT = _glProgramUniform4i");
#if 0 // FIXME: has unhandled types
void glCompressedTexSubImage3D (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint zoffset, GLsizei width, GLsizei height, GLsizei depth, GLenum format, GLsizei imageSize, const GLvoid* data) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  uint64_t host_arg8 = (uint64_t)guest_arg8; 
  uint64_t host_arg9 = (uint64_t)guest_arg9; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7, guest_arg8, guest_arg9, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  // No post-process for guest_arg8 
  // No post-process for guest_arg9 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniform2f (GLint location, GLfloat x, GLfloat y) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform4fv(GLuint program, GLint location, GLsizei count, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform4fvEXT\n _glProgramUniform4fvEXT = _glProgramUniform4fv");
#if 0 // FIXME: has unhandled types
void glColorPointer (GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLvoid * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLvoid * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLvoid * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetClipPlanef (GLenum pname, GLfloat *equation) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glGetFramebufferAttachmentParameteriv(GLenum target, GLenum attachment, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
__asm__(".global _glGetFramebufferAttachmentParameterivOES\n _glGetFramebufferAttachmentParameterivOES = _glGetFramebufferAttachmentParameteriv");
#if 0 // FIXME: has unhandled types
void glGetVertexAttribPointerv (GLuint index, GLenum pname, GLvoid** pointer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLvoid** */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLvoid** */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLvoid** */ 
  // return void
}
#endif
GLvoid glProgramUniform3ui(GLuint program, GLint location, GLuint x, GLuint y, GLuint z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
__asm__(".global _glProgramUniform3uiEXT\n _glProgramUniform3uiEXT = _glProgramUniform3ui");
#if 0 // FIXME: has unhandled types
void glSamplerParameterf (GLuint sampler, GLenum pname, GLfloat param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetSynciv (GLsync sync, GLenum pname, GLsizei bufSize, GLsizei* length, GLint* values) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLsync */ 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLsync */, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLint* */);
  /* postCall: unhandled type GLsync */ 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniform4uiv (GLint location, GLsizei count, const GLuint* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetShaderInfoLog (GLuint shader, GLsizei bufsize, GLsizei* length, GLchar* infolog) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLchar* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLchar* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniformMatrix4fv(GLuint program, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniformMatrix4fvEXT\n _glProgramUniformMatrix4fvEXT = _glProgramUniformMatrix4fv");
void glAlphaFuncx (GLenum func, GLclampx ref) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
void glCopyTexImage2D (GLenum target, GLint level, GLenum internalformat, GLint x, GLint y, GLsizei width, GLsizei height, GLint border) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  // return void
}
#if 0 // FIXME: has unhandled types
void glTexParameterxv (GLenum target, GLenum pname, const GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfixed * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glGetObjectLabel(GLenum type, GLuint object, GLsizei bufSize, GLsizei *length, GLchar *label) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLsizei * */ 
  /* declaration: unhandled type GLchar * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLsizei * */, /* parameterToBePassed: unhandled type GLchar * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLsizei * */ 
  /* postCall: unhandled type GLchar * */ 
  // return void
}
#endif
__asm__(".global _glGetObjectLabelEXT\n _glGetObjectLabelEXT = _glGetObjectLabel");
#if 0 // FIXME: has unhandled types
void glDrawRangeElements (GLenum mode, GLuint start, GLuint end, GLsizei count, GLenum type, const GLvoid* indices) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
void glBlendEquation (GLenum mode) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glVertexAttrib4fv (GLuint indx, const GLfloat* values) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glClearBufferfv (GLenum buffer, GLint drawbuffer, const GLfloat* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetProgramInfoLog (GLuint program, GLsizei bufsize, GLsizei* length, GLchar* infolog) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLchar* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLchar* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetTexParameteriv (GLenum target, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glMaterialxv (GLenum face, GLenum pname, const GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfixed * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniform4fv (GLint location, GLsizei count, const GLfloat* v) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
GLvoid glEndQuery(GLenum target) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
__asm__(".global _glEndQueryEXT\n _glEndQueryEXT = _glEndQuery");
#if 0 // FIXME: has unhandled types
void glGetVertexAttribIuiv (GLuint index, GLenum pname, GLuint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
void glMultiTexCoord4x (GLenum target, GLfixed s, GLfixed t, GLfixed r, GLfixed q) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
GLboolean glIsRenderbuffer(GLuint renderbuffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
__asm__(".global _glIsRenderbufferOES\n _glIsRenderbufferOES = _glIsRenderbuffer");
#if 0 // FIXME: has unhandled types
void glCompressedTexSubImage2D (GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height, GLenum format, GLsizei imageSize, const GLvoid* data) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform3iv(GLuint program, GLint location, GLsizei count, const GLint *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLint * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform3ivEXT\n _glProgramUniform3ivEXT = _glProgramUniform3iv");
#if 0 // FIXME: has unhandled types
void glMaterialfv (GLenum face, GLenum pname, const GLfloat *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
void glUseProgram (GLuint program) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetQueryiv (GLenum target, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glVertexAttrib2f (GLuint indx, GLfloat x, GLfloat y) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glReadPixels (GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, GLvoid* pixels) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  /* declaration: unhandled type GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, /* parameterToBePassed: unhandled type GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  /* postCall: unhandled type GLvoid* */ 
  // return void
}
#endif
void glBindBufferBase (GLenum target, GLuint index, GLuint buffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
void glReadBuffer (GLenum mode) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glGetClipPlanex (GLenum pname, GLfixed eqn[4]) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glLightxv (GLenum light, GLenum pname, const GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfixed * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
GLboolean glIsTexture (GLuint texture) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
#if 0 // FIXME: has unhandled types
void glDepthRangef (GLclampf zNear, GLclampf zFar) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLclampf */ 
  /* declaration: unhandled type GLclampf */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLclampf */, /* parameterToBePassed: unhandled type GLclampf */);
  /* postCall: unhandled type GLclampf */ 
  /* postCall: unhandled type GLclampf */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glFogfv (GLenum pname, const GLfloat *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniformMatrix4fv (GLint location, GLsizei count, GLboolean transpose, const GLfloat* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glShaderSource (GLuint shader, GLsizei count, const GLchar* const *string, const GLint* length) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLchar* const * */ 
  /* declaration: unhandled type const GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLchar* const * */, /* parameterToBePassed: unhandled type const GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLchar* const * */ 
  /* postCall: unhandled type const GLint* */ 
  // return void
}
#endif
GLvoid glTexStorage2D(GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
__asm__(".global _glTexStorage2DEXT\n _glTexStorage2DEXT = _glTexStorage2D");
#if 0 // FIXME: has unhandled types
void glWaitSync (GLsync sync, GLbitfield flags, GLuint64 timeout) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLsync */ 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLsync */, guest_arg1, guest_arg2);
  /* postCall: unhandled type GLsync */ 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetActiveUniformsiv (GLuint program, GLsizei uniformCount, const GLuint* uniformIndices, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLuint* */, guest_arg3, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLuint* */ 
  // No post-process for guest_arg3 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLsync glFenceSync (GLenum condition, GLbitfield flags) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* returnLine: unhandled type GLsync */
}
#endif
void glStencilOp (GLenum fail, GLenum zfail, GLenum zpass) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
GLvoid glBeginQuery(GLenum target, GLuint id) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
__asm__(".global _glBeginQueryEXT\n _glBeginQueryEXT = _glBeginQuery");
#if 0 // FIXME: has unhandled types
void glFogxv (GLenum pname, const GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfixed * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniform3uiv (GLint location, GLsizei count, const GLuint* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetMaterialxv (GLenum face, GLenum pname, GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfixed * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfixed * */ 
  // return void
}
#endif
void glLoadPaletteFromModelViewMatrix(void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
__asm__(".global _glLoadPaletteFromModelViewMatrixOES\n _glLoadPaletteFromModelViewMatrixOES = _glLoadPaletteFromModelViewMatrix");
#if 0 // FIXME: has unhandled types
void glWeightPointer(GLint size, GLenum type, GLsizei stride, const GLvoid *pointer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLvoid * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLvoid * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLvoid * */ 
  // return void
}
#endif
__asm__(".global _glWeightPointerOES\n _glWeightPointerOES = _glWeightPointer");
GLvoid glBindProgramPipeline(GLuint pipeline) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
__asm__(".global _glBindProgramPipelineEXT\n _glBindProgramPipelineEXT = _glBindProgramPipeline");
#if 0 // FIXME: has unhandled types
void glGetActiveUniform (GLuint program, GLuint index, GLsizei bufsize, GLsizei* length, GLint* size, GLenum* type, GLchar* name) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type GLsizei* */ 
  /* declaration: unhandled type GLint* */ 
  /* declaration: unhandled type GLenum* */ 
  /* declaration: unhandled type GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type GLsizei* */, /* parameterToBePassed: unhandled type GLint* */, /* parameterToBePassed: unhandled type GLenum* */, /* parameterToBePassed: unhandled type GLchar* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type GLsizei* */ 
  /* postCall: unhandled type GLint* */ 
  /* postCall: unhandled type GLenum* */ 
  /* postCall: unhandled type GLchar* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glVertexAttribPointer (GLuint indx, GLint size, GLenum type, GLboolean normalized, GLsizei stride, const GLvoid* ptr) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
void glUniform4i (GLint location, GLint x, GLint y, GLint z, GLint w) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
void glClearStencil (GLint s) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGenSamplers (GLsizei count, GLuint* samplers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
void glEnableClientState (GLenum array) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glUniform2iv (GLint location, GLsizei count, const GLint* v) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLint* */ 
  // return void
}
#endif
void glColorMask (GLboolean red, GLboolean green, GLboolean blue, GLboolean alpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
#if 0 // FIXME: has unhandled types
void glDrawTexsv(const GLshort *coords) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type const GLshort * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type const GLshort * */);
  /* postCall: unhandled type const GLshort * */ 
  // return void
}
#endif
__asm__(".global _glDrawTexsvOES\n _glDrawTexsvOES = _glDrawTexsv");
GLvoid glBlendEquationSeparate(GLenum modeRGB, GLenum modeAlpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
__asm__(".global _glBlendEquationSeparateOES\n _glBlendEquationSeparateOES = _glBlendEquationSeparate");
void glGenerateMipmap (GLenum target) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glDisableClientState (GLenum array) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glDeleteRenderbuffers(GLsizei n, const GLuint* renderbuffers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
__asm__(".global _glDeleteRenderbuffersOES\n _glDeleteRenderbuffersOES = _glDeleteRenderbuffers");
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniformMatrix3x4fv(GLuint program, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniformMatrix3x4fvEXT\n _glProgramUniformMatrix3x4fvEXT = _glProgramUniformMatrix3x4fv");
#if 0 // FIXME: has unhandled types
void glUniform4f (GLint location, GLfloat x, GLfloat y, GLfloat z, GLfloat w) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
GLvoid glValidateProgramPipeline(GLuint pipeline) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
__asm__(".global _glValidateProgramPipelineEXT\n _glValidateProgramPipelineEXT = _glValidateProgramPipeline");
GLvoid glResolveMultisampleFramebuffer(void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
__asm__(".global _glResolveMultisampleFramebufferAPPLE\n _glResolveMultisampleFramebufferAPPLE = _glResolveMultisampleFramebuffer");
void glTranslatex (GLfixed x, GLfixed y, GLfixed z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
void glBindRenderbuffer (GLenum target, GLuint renderbuffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
void glBindTransformFeedback (GLenum target, GLuint id) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
GLboolean glIsSampler (GLuint sampler) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
#if 0 // FIXME: has unhandled types
void glColor4f (GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid * glMapBufferRange(GLenum target, GLintptr offset, GLsizeiptr length, GLbitfield access) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLintptr */ 
  /* declaration: unhandled type GLsizeiptr */ 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLintptr */, /* parameterToBePassed: unhandled type GLsizeiptr */, guest_arg3);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLintptr */ 
  /* postCall: unhandled type GLsizeiptr */ 
  // No post-process for guest_arg3 
  /* returnLine: unhandled type GLvoid * */
}
#endif
__asm__(".global _glMapBufferRangeEXT\n _glMapBufferRangeEXT = _glMapBufferRange");
#if 0 // FIXME: has unhandled types
void glMaterialf (GLenum face, GLenum pname, GLfloat param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
void glBlendFuncSeparate (GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetTexEnvfv (GLenum env, GLenum pname, GLfloat *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat * */ 
  // return void
}
#endif
void glDrawArrays (GLenum mode, GLint first, GLsizei count) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glUniform2uiv (GLint location, GLsizei count, const GLuint* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
GLvoid glVertexAttribDivisor(GLuint index, GLuint divisor) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
__asm__(".global _glVertexAttribDivisorEXT\n _glVertexAttribDivisorEXT = _glVertexAttribDivisor");
#if 0 // FIXME: has unhandled types
void glLightfv (GLenum light, GLenum pname, const GLfloat *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniformMatrix4x3fv (GLint location, GLsizei count, GLboolean transpose, const GLfloat* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
void glClearDepthx (GLclampx depth) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glReleaseShaderCompiler (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
#if 0 // FIXME: has unhandled types
void glUniform4iv (GLint location, GLsizei count, const GLint* v) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glBindAttribLocation (GLuint program, GLuint index, const GLchar* name) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLchar* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLchar* */ 
  // return void
}
#endif
void glProgramParameteri (GLuint program, GLenum pname, GLint value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetTexEnviv (GLenum env, GLenum pname, GLint *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetProgramiv (GLuint program, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glDeleteRenderbuffers (GLsizei n, const GLuint* renderbuffers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform4uiv(GLuint program, GLint location, GLsizei count, const GLuint *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLuint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLuint * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform4uivEXT\n _glProgramUniform4uivEXT = _glProgramUniform4uiv");
#if 0 // FIXME: has unhandled types
void glClearBufferuiv (GLenum buffer, GLint drawbuffer, const GLuint* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
void glPolygonOffsetx (GLfixed factor, GLfixed units) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetBufferPointerv (GLenum target, GLenum pname, GLvoid** params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLvoid** */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLvoid** */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLvoid** */ 
  // return void
}
#endif
void glClientActiveTexture (GLenum texture) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glLogicOp (GLenum opcode) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glLinkProgram (GLuint program) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glSampleCoveragex (GLclampx value, GLboolean invert) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
void glStencilFunc (GLenum func, GLint ref, GLuint mask) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glLightModelf (GLenum pname, GLfloat param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
GLboolean glIsVertexArray(GLuint array) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
__asm__(".global _glIsVertexArrayOES\n _glIsVertexArrayOES = _glIsVertexArray");
void glTexStorage2D (GLenum target, GLsizei levels, GLenum internalformat, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
#if 0 // FIXME: has unhandled types
void glDeleteFramebuffers (GLsizei n, const GLuint* framebuffers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform1f(GLuint program, GLint location, GLfloat x) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform1fEXT\n _glProgramUniform1fEXT = _glProgramUniform1f");
#if 0 // FIXME: has unhandled types
void glGetUniformiv (GLuint program, GLint location, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetUniformuiv (GLuint program, GLint location, GLuint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform1uiv(GLuint program, GLint location, GLsizei count, const GLuint *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLuint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLuint * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform1uivEXT\n _glProgramUniform1uivEXT = _glProgramUniform1uiv");
void glBindTexture (GLenum target, GLuint texture) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glGetProgramPipelineInfoLog(GLuint pipeline, GLsizei bufSize, GLsizei *length, GLchar *infoLog) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLsizei * */ 
  /* declaration: unhandled type GLchar * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLsizei * */, /* parameterToBePassed: unhandled type GLchar * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLsizei * */ 
  /* postCall: unhandled type GLchar * */ 
  // return void
}
#endif
__asm__(".global _glGetProgramPipelineInfoLogEXT\n _glGetProgramPipelineInfoLogEXT = _glGetProgramPipelineInfoLog");
void glUniform1ui (GLint location, GLuint v0) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform3fv(GLuint program, GLint location, GLsizei count, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform3fvEXT\n _glProgramUniform3fvEXT = _glProgramUniform3fv");
#if 0 // FIXME: has unhandled types
void glPointSize (GLfloat size) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
void glTexParameteri (GLenum target, GLenum pname, GLint param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
GLvoid glProgramUniform2ui(GLuint program, GLint location, GLuint x, GLuint y) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
__asm__(".global _glProgramUniform2uiEXT\n _glProgramUniform2uiEXT = _glProgramUniform2ui");
#if 0 // FIXME: has unhandled types
void glClipPlanex (GLenum plane, const GLfixed *equation) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfixed * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
void glFinish (void) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
#if 0 // FIXME: has unhandled types
void glUniform1uiv (GLint location, GLsizei count, const GLuint* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetIntegeri_v (GLenum target, GLuint index, GLint* data) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetInteger64v(GLenum pname, GLint64 *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLint64 * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLint64 * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLint64 * */ 
  // return void
}
#endif
__asm__(".global _glGetInteger64vAPPLE\n _glGetInteger64vAPPLE = _glGetInteger64v");
void glBindFramebuffer (GLenum target, GLuint framebuffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
GLvoid glGetQueryObjectuiv(GLuint id, GLenum pname, GLuint *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLuint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLuint * */ 
  // return void
}
#endif
__asm__(".global _glGetQueryObjectuivEXT\n _glGetQueryObjectuivEXT = _glGetQueryObjectuiv");
void glDrawArraysInstanced (GLenum mode, GLint first, GLsizei count, GLsizei instancecount) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
void glVertexAttribI4ui (GLuint index, GLuint x, GLuint y, GLuint z, GLuint w) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
#if 0 // FIXME: has unhandled types
void glClearColor (GLfloat red, GLfloat green, GLfloat blue, GLfloat alpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glCompressedTexImage3D (GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height, GLsizei depth, GLint border, GLsizei imageSize, const GLvoid* data) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_arg5 = (uint64_t)guest_arg5; 
  uint64_t host_arg6 = (uint64_t)guest_arg6; 
  uint64_t host_arg7 = (uint64_t)guest_arg7; 
  /* declaration: unhandled type const GLvoid* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4, guest_arg5, guest_arg6, guest_arg7, /* parameterToBePassed: unhandled type const GLvoid* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // No post-process for guest_arg5 
  // No post-process for guest_arg6 
  // No post-process for guest_arg7 
  /* postCall: unhandled type const GLvoid* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLint glGetFragDataLocation (GLuint program, const GLchar *name) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLchar * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLchar * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLchar * */ 
  return (GLint)host_ret;
}
#endif
void glDrawTexi(GLint x, GLint y, GLint z, GLint width, GLint height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
__asm__(".global _glDrawTexiOES\n _glDrawTexiOES = _glDrawTexi");
#if 0 // FIXME: has unhandled types
GLvoid glGetProgramPipelineiv(GLuint pipeline, GLenum pname, GLint *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint * */ 
  // return void
}
#endif
__asm__(".global _glGetProgramPipelineivEXT\n _glGetProgramPipelineivEXT = _glGetProgramPipelineiv");
#if 0 // FIXME: has unhandled types
GLuint glCreateShaderProgramv(GLenum type, GLsizei count, const GLchar* const *strings) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLchar* const * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLchar* const * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLchar* const * */ 
  return (GLuint)host_ret;
}
#endif
__asm__(".global _glCreateShaderProgramvEXT\n _glCreateShaderProgramvEXT = _glCreateShaderProgramv");
void glColor4x (GLfixed red, GLfixed green, GLfixed blue, GLfixed alpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
#if 0 // FIXME: has unhandled types
GLuint glGetUniformBlockIndex (GLuint program, const GLchar* uniformBlockName) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLchar* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLchar* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLchar* */ 
  return (GLuint)host_ret;
}
#endif
#if 0 // FIXME: has unhandled types
void glClearBufferiv (GLenum buffer, GLint drawbuffer, const GLint* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glTexEnvf (GLenum target, GLenum pname, GLfloat param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniformMatrix2x3fv (GLint location, GLsizei count, GLboolean transpose, const GLfloat* value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glVertexAttribI4uiv (GLuint index, const GLuint* v) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glVertexAttrib1f (GLuint indx, GLfloat x) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform2iv(GLuint program, GLint location, GLsizei count, const GLint *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  /* declaration: unhandled type const GLint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, /* parameterToBePassed: unhandled type const GLint * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  /* postCall: unhandled type const GLint * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform2ivEXT\n _glProgramUniform2ivEXT = _glProgramUniform2iv");
#if 0 // FIXME: has unhandled types
const GLubyte* glGetString (GLenum name) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  /* returnLine: unhandled type const GLubyte* */
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniformMatrix2fv(GLuint program, GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, /* parameterToBePassed: unhandled type const GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glProgramUniformMatrix2fvEXT\n _glProgramUniformMatrix2fvEXT = _glProgramUniformMatrix2fv");
GLvoid glBlendFuncSeparate(GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
__asm__(".global _glBlendFuncSeparateOES\n _glBlendFuncSeparateOES = _glBlendFuncSeparate");
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform2f(GLuint program, GLint location, GLfloat x, GLfloat y) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform2fEXT\n _glProgramUniform2fEXT = _glProgramUniform2f");
void glActiveTexture (GLenum texture) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
void glUniform3ui (GLint location, GLuint v0, GLuint v1, GLuint v2) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetInteger64i_v (GLenum target, GLuint index, GLint64* data) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint64* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint64* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint64* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glLightModelxv (GLenum pname, const GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLfixed * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glDrawTexfv(const GLfloat *coords) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type const GLfloat * */);
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
__asm__(".global _glDrawTexfvOES\n _glDrawTexfvOES = _glDrawTexfv");
void glTexEnvi (GLenum target, GLenum pname, GLint param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGetVertexAttribIiv (GLuint index, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glDeleteSamplers (GLsizei count, const GLuint* samplers) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetRenderbufferParameteriv (GLenum target, GLenum pname, GLint* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLint* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glMultMatrixf (const GLfloat *m) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type const GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type const GLfloat * */);
  /* postCall: unhandled type const GLfloat * */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glSampleCoverage (GLclampf value, GLboolean invert) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLclampf */ 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLclampf */, guest_arg1);
  /* postCall: unhandled type GLclampf */ 
  // No post-process for guest_arg1 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetPointerv (GLenum pname, void **params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type void ** */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type void ** */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type void ** */ 
  // return void
}
#endif
GLvoid glDrawArraysInstanced(GLenum mode, GLint first, GLsizei count, GLsizei instanceCount) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
__asm__(".global _glDrawArraysInstancedEXT\n _glDrawArraysInstancedEXT = _glDrawArraysInstanced");
#if 0 // FIXME: has unhandled types
void glDrawTexxv(const GLfixed *coords) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type const GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type const GLfixed * */);
  /* postCall: unhandled type const GLfixed * */ 
  // return void
}
#endif
__asm__(".global _glDrawTexxvOES\n _glDrawTexxvOES = _glDrawTexxv");
GLboolean glIsBuffer (GLuint buffer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
#if 0 // FIXME: has unhandled types
GLvoid glGenVertexArrays(GLsizei n, GLuint *arrays) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint * */ 
  // return void
}
#endif
__asm__(".global _glGenVertexArraysOES\n _glGenVertexArraysOES = _glGenVertexArrays");
GLboolean glIsQuery (GLuint id) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
GLboolean glIsEnabled (GLenum cap) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
GLuint glCreateShader (GLenum type) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLuint)host_ret;
}
#if 0 // FIXME: has unhandled types
GLvoid glDeleteProgramPipelines(GLsizei n, const GLuint *pipelines) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint * */ 
  // return void
}
#endif
__asm__(".global _glDeleteProgramPipelinesEXT\n _glDeleteProgramPipelinesEXT = _glDeleteProgramPipelines");
GLenum glCheckFramebufferStatus(GLenum target) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLenum)host_ret;
}
__asm__(".global _glCheckFramebufferStatusOES\n _glCheckFramebufferStatusOES = _glCheckFramebufferStatus");
#if 0 // FIXME: has unhandled types
void glGetTexEnvxv (GLenum env, GLenum pname, GLfixed *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfixed * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfixed * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfixed * */ 
  // return void
}
#endif
void glUniform1i (GLint location, GLint x) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
void glDrawBuffers (GLsizei n, const GLenum* bufs) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLenum* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLenum* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLenum* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glScalef (GLfloat x, GLfloat y, GLfloat z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glDeleteTextures (GLsizei n, const GLuint* textures) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
void glFramebufferTextureLayer (GLenum target, GLenum attachment, GLuint texture, GLint level, GLint layer) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_arg4 = (uint64_t)guest_arg4; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3, guest_arg4);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // No post-process for guest_arg4 
  // return void
}
#if 0 // FIXME: has unhandled types
void glTexParameterfv (GLenum target, GLenum pname, const GLfloat* params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glPushGroupMarker(GLsizei length, const GLchar *marker) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLchar * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLchar * */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLchar * */ 
  // return void
}
#endif
__asm__(".global _glPushGroupMarkerEXT\n _glPushGroupMarkerEXT = _glPushGroupMarker");
#if 0 // FIXME: has unhandled types
void glDeleteQueries (GLsizei n, const GLuint* ids) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type const GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type const GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type const GLuint* */ 
  // return void
}
#endif
void glDetachShader (GLuint program, GLuint shader) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // return void
}
#if 0 // FIXME: has unhandled types
void glPointParameterf (GLenum pname, GLfloat param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glRotatef (GLfloat angle, GLfloat x, GLfloat y, GLfloat z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
GLboolean glIsProgramPipeline(GLuint pipeline) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  return (GLboolean)host_ret;
}
__asm__(".global _glIsProgramPipelineEXT\n _glIsProgramPipelineEXT = _glIsProgramPipeline");
#if 0 // FIXME: has unhandled types
GLvoid glProgramUniform3f(GLuint program, GLint location, GLfloat x, GLfloat y, GLfloat z) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
__asm__(".global _glProgramUniform3fEXT\n _glProgramUniform3fEXT = _glProgramUniform3f");
GLvoid glBlendEquation(GLenum mode)) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd);
  // return void
}
__asm__(".global _glBlendEquationOES\n _glBlendEquationOES = _glBlendEquation");
void glFrontFace (GLenum mode) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glGenVertexArrays (GLsizei n, GLuint* arrays) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLuint* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLuint* */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLuint* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
GLvoid glGetBufferPointerv(GLenum target, GLenum pname, GLvoid **params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLvoid ** */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLvoid ** */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLvoid ** */ 
  // return void
}
#endif
__asm__(".global _glGetBufferPointervOES\n _glGetBufferPointervOES = _glGetBufferPointerv");
#if 0 // FIXME: has unhandled types
void glTexParameterf (GLenum target, GLenum pname, GLfloat param) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glUniform1f (GLint location, GLfloat x) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  /* declaration: unhandled type GLfloat */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, /* parameterToBePassed: unhandled type GLfloat */);
  // No post-process for guest_arg0 
  /* postCall: unhandled type GLfloat */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glGetMaterialfv (GLenum face, GLenum pname, GLfloat *params) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type GLfloat * */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type GLfloat * */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type GLfloat * */ 
  // return void
}
#endif
void glMatrixMode (GLenum mode) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0);
  // No post-process for guest_arg0 
  // return void
}
#if 0 // FIXME: has unhandled types
void glUniform1fv (GLint location, GLsizei count, const GLfloat* v) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  /* declaration: unhandled type const GLfloat* */ 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, /* parameterToBePassed: unhandled type const GLfloat* */);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  /* postCall: unhandled type const GLfloat* */ 
  // return void
}
#endif
#if 0 // FIXME: has unhandled types
void glWaitSync(GLsync sync, GLbitfield flags, GLuint64 timeout) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  /* declaration: unhandled type GLsync */ 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, /* parameterToBePassed: unhandled type GLsync */, guest_arg1, guest_arg2);
  /* postCall: unhandled type GLsync */ 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // return void
}
#endif
__asm__(".global _glWaitSyncAPPLE\n _glWaitSyncAPPLE = _glWaitSync");
void glScissor (GLint x, GLint y, GLsizei width, GLsizei height) {
  printf("DBG: call %s\n", __func__);
  static uint64_t _host_cmd;
  if(!_host_cmd) _host_cmd = LC32Dlsym(__func__, YES);
  uint64_t host_arg0 = (uint64_t)guest_arg0; 
  uint64_t host_arg1 = (uint64_t)guest_arg1; 
  uint64_t host_arg2 = (uint64_t)guest_arg2; 
  uint64_t host_arg3 = (uint64_t)guest_arg3; 
  uint64_t host_ret = LC32InvokeHostCRet32(LC32InvokeHostCArgs64, _host_cmd, guest_arg0, guest_arg1, guest_arg2, guest_arg3);
  // No post-process for guest_arg0 
  // No post-process for guest_arg1 
  // No post-process for guest_arg2 
  // No post-process for guest_arg3 
  // return void
}
