#version 460 core

uniform sampler2D acc_frame;

in vec2 fragCoord;
in vec2 fragTexCoord;

out vec4 fragColor;

void main() {
	fragColor = texture(acc_frame, fragTexCoord);
}