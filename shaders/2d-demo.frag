#version 410 core

layout(location = 0) out vec4 fragColor;

uniform vec2 u_resolution;
uniform vec2 u_mouse;
uniform float u_time;

float sdCircle(vec2 p, float r) {
  return length(p) - r;
}

vec3 render(vec2 uv) {
  vec3 col = vec3(0.12, 0.12, 0.15);

  // // grid
  // vec2 grid = abs(fract(uv * 2.0) - 0.5);
  // float gridLine = min(grid.x, grid.y);
  // col = mix(col, vec3(0.2, 0.2, 0.25), 1.0 - smoothstep(0.0, 0.02, gridLine - 0.02));
  //
  // // axes
  // col = mix(col, vec3(0.35, 0.35, 0.4), 1.0 - smoothstep(0.0, 0.01, abs(uv.x) - 0.005));
  // col = mix(col, vec3(0.35, 0.35, 0.4), 1.0 - smoothstep(0.0, 0.01, abs(uv.y) - 0.005));

  float r = 0.5;
  vec2 center = vec2(0.0);
  float d = sdCircle(uv - center, r);

  // filled interior - faint
  col = mix(col, vec3(0.2, 0.5, 0.9), 0.12 * (1.0 - smoothstep(0.0, 0.01, d)));

  // circle border
  col = mix(col, vec3(0.3, 0.6, 1.0), 1.0 - smoothstep(0.0, 0.008, abs(d)));

  // distance field visualisation - rings
  float rings = 0.5 + 0.5 * sin(d * 40.0);
  rings = pow(rings, 6.0);
  vec3 ringCol = d < 0.0 ? vec3(0.2, 0.6, 1.0) : vec3(1.0, 0.5, 0.2);
  col = mix(col, ringCol, rings * 0.18);

  // mouse point
  vec2 mouse = (u_mouse / u_resolution) * 2.0 - 1.0;
  mouse.x *= u_resolution.x / u_resolution.y;
  mouse.y = -mouse.y;

  float dMouse = sdCircle(uv - center, r);
  float mouseDist = length(uv - mouse);

  // line from mouse to nearest point on circle
  vec2 nearest = center + normalize(mouse - center) * r;
  float lineT = clamp(dot(uv - mouse, nearest - mouse) / dot(nearest - mouse, nearest - mouse), 0.0, 1.0);
  vec2 lineP = mouse + lineT * (nearest - mouse);
  float lineDist = length(uv - lineP);
  float dMouseVal = sdCircle(mouse - center, r);
  vec3 lineColor = dMouseVal < 0.0 ? vec3(0.2, 0.9, 0.5) : vec3(1.0, 0.35, 0.35);
  col = mix(col, lineColor, (1.0 - smoothstep(0.0, 0.006, lineDist)) * 0.85);

  // nearest point on circle dot
  col = mix(col, vec3(1.0), 1.0 - smoothstep(0.0, 0.018, length(uv - nearest) - 0.012));
  col = mix(col, lineColor, 1.0 - smoothstep(0.0, 0.015, length(uv - nearest) - 0.008));

  // mouse dot
  col = mix(col, vec3(1.0), 1.0 - smoothstep(0.0, 0.018, mouseDist - 0.016));
  col = mix(col, lineColor, 1.0 - smoothstep(0.0, 0.015, mouseDist - 0.012));

  // center dot
  col = mix(col, vec3(1.0), 1.0 - smoothstep(0.0, 0.015, length(uv) - 0.01));
  col = mix(col, vec3(0.9, 0.9, 0.3), 1.0 - smoothstep(0.0, 0.012, length(uv) - 0.007));

  return col;
}

void main() {
  vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / u_resolution.y;
  vec3 col = render(uv);
  col = pow(col, vec3(0.4545));
  fragColor = vec4(col, 1.0);
}
