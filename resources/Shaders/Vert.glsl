#version 460 core

layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 tex_coord;

out vec2 fragCoord;
out vec2 fragTexCoord;

const vec2 madd = vec2(0.5);

void main() {
	gl_Position = vec4(pos, 0.0, 1.0);
	fragCoord = pos * madd + madd;
	fragTexCoord = tex_coord;
}