#version 460 core

uniform sampler2D iRawFrame;
uniform sampler2D iAccumulationFrame;

in vec2 fragCoord;
in vec2 fragTexCoord;

out vec4 fragColor;

void main() {
	fragColor = texture(iAccumulationFrame, fragTexCoord);
}