#version 460 core

uniform uint  runframe;
uniform bool  reset;

uniform sampler2D raw_frame;
uniform sampler2D last_frame;

in vec2 fragCoord;
in vec2 fragTexCoord;

out vec4 fragColor;

void main() {
	float weight = float(runframe);
	if (runframe <= 1 || !reset)
		fragColor = vec4((texture(last_frame, fragTexCoord).xyz * weight + texture(raw_frame, fragTexCoord).xyz) / (weight + 1.0), 1);
	else
		fragColor = texture(raw_frame, fragTexCoord);
}