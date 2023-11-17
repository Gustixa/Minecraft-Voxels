#pragma once

#include "Include.h"

#include "Camera.h"

#include "EBO.h"
#include "FBO.h"
#include "FBT.h"
#include "VAO.h"
#include "VBO.h"
#include "Texture.h"
#include "Shader_Program.h"

struct GLSL_Renderer {
	vector<GLfloat> vertices;
	vector<GLuint> faces;

	double runtime;
	size_t runframe;
	uvec2  resolution;
	bool   reset;

	Camera camera;

	double camera_move_sensitivity;
	double camera_view_sensitivity;
	vector<bool> keys;
	dvec2  last_mouse;

	clock_t last_time;
	clock_t current_time;
	double window_time;
	double frame_time;

	VAO main_vao;
	VBO main_vbo;
	EBO main_ebo;
	FBT raw_tex;
	FBT acc_tex;
	FBO raw_fbo;
	FBO acc_fbo;
	Shader_Program raw_fp;
	Shader_Program acc_fp;
	Shader_Program pp_fp;

	GLSL_Renderer();

	void recompile();
	void init();

	static void framebuffer_size_callback(GLFWwindow* window, int width, int height);
	static void cursor_position_callback(GLFWwindow* window, double xpos, double ypos);
	static void mouse_button_callback(GLFWwindow* window, int button, int action, int mods);
	static void scroll_callback(GLFWwindow* window, double xoffset, double yoffset);
	static void key_callback(GLFWwindow* window, int key, int scancode, int action, int mods);
};