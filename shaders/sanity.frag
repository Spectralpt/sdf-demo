#version 410

uniform vec2 u_resolution; // viewport size in pixels (width, height)

out vec4 fragColor;
uniform sampler2D u_ground_disp;


void main() {
    vec2 fragCoord = gl_FragCoord.xy;

    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    fragColor = vec4(vec3(texture(u_ground_disp, uv).r),1.0);
}
