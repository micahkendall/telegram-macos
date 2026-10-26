#pragma once
#define GL_SILENCE_DEPRECATION 1
#include <OpenGL/gl.h>
#include <OpenGL/glext.h>
#ifdef __cplusplus
extern "C" {
#endif
void TGMacGLShaderSource(GLuint shader, GLsizei count, const GLchar *const *strings, const GLint *lengths);
void TGMacGLFlush(void);
void TGMacGLFinish(void);
#ifdef __cplusplus
}
#endif
#define glShaderSource TGMacGLShaderSource
#define glFlush TGMacGLFlush
#define glFinish TGMacGLFinish
#define glClearDepthf glClearDepth
#define GL_RED_EXT GL_RED
#define GL_RG_EXT GL_RG
