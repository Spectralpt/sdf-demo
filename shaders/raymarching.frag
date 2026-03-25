#version 410 core

layout(location = 0) out vec4 fragColor;

uniform vec2 u_resolution;
uniform vec2 u_mouse;
uniform float u_time;

#define PI 3.14159265

float sdCircle(vec2 p, float r) {
  return length(p) - r;
}

float sdBox2(vec2 p, vec2 b) {
  vec2 d = abs(p) - b;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// scene - a few circles and a box
float map(vec2 p) {
  float d = sdCircle(p - vec2(0.3, 0.2), 0.18);
  d = min(d, sdCircle(p - vec2(-0.4, -0.1), 0.13));
  d = min(d, sdCircle(p - vec2(0.1, -0.35), 0.1));
  d = min(d, sdBox2(p - vec2(-0.2, 0.35), vec2(0.12, 0.08)));
  return d;
}

void main() {
  vec2 uv = (gl_FragCoord.xy * 2.0 - u_resolution.xy) / u_resolution.y;
  vec3 col = vec3(0.05, 0.05, 0.05);

  // // grid
  // vec2 grid = abs(fract(uv * 4.0) - 0.5);
  // float gridLine = min(grid.x, grid.y);
  // col = mix(col, vec3(0.18, 0.18, 0.22), 1.0 - smoothstep(0.0, 0.02, gridLine - 0.02));

  // draw scene shapes filled
  float scene = map(uv);
  col = mix(col, vec3(0.25, 0.35, 0.5), 1.0 - smoothstep(0.0, 0.004, scene));

  // scene outline
  col = mix(col, vec3(0.5, 0.75, 1.0), 1.0 - smoothstep(0.0, 0.006, abs(scene)));

  // ray origin = left side of screen, fixed
  vec2 ro = vec2(-0.85, 0.0);

  // ray direction points toward mouse
  vec2 mouse = (u_mouse / u_resolution) * 2.0 - 1.0;
  mouse.x *= u_resolution.x / u_resolution.y;
  mouse.y = -mouse.y;
  vec2 rd = normalize(mouse - ro);

  // raymarch
  const int MAX_STEPS = 10;
  float t = 0.0;
  float hit = -1.0;
  float steps[10];
  vec2 positions[10];
  float distances[10];

  for (int i = 0; i < MAX_STEPS; i++) {
    vec2 p = ro + rd * t;
    float d = map(p);
    steps[i] = t;
    positions[i] = p;
    distances[i] = d;

    if (d < 0.004) {
      hit = float(i);
      break;
    }
    if (t > 3.0) {
      break;
    }
    t += d;
  }

  // draw the safe radius circles at each step
  for (int i = 0; i < MAX_STEPS; i++) {
    if (steps[i] == 0.0 && i > 0) break;
    float r = distances[i];
    float circleDist = abs(length(uv - positions[i]) - r);
    float alpha = 0.5 - float(i) * 0.04;
    col = mix(col, vec3(1.0, 0.8, 0.2), (1.0 - smoothstep(0.0, 0.006, circleDist)) * alpha);
  }

  // draw the ray line up to final point
  {
    vec2 rayEnd = ro + rd * t;
    vec2 toUV = uv - ro;
    float proj = clamp(dot(toUV, rd), 0.0, t);
    vec2 closest = ro + rd * proj;
    float lineDist = length(uv - closest);
    col = mix(col, vec3(1.0, 0.55, 0.1), (1.0 - smoothstep(0.0, 0.005, lineDist)) * 0.9);
  }

  // draw step points along the ray
  for (int i = 0; i < MAX_STEPS; i++) {
    if (steps[i] == 0.0 && i > 0) break;
    float pd = length(uv - positions[i]);
    // outer white ring
    col = mix(col, vec3(1.0), 1.0 - smoothstep(0.0, 0.012, pd - 0.009));
    // inner color - yellow if marching, red if hit
    vec3 dotCol = (hit >= 0.0 && i == int(hit)) ? vec3(1.0, 0.2, 0.2) : vec3(1.0, 0.75, 0.1);
    col = mix(col, dotCol, 1.0 - smoothstep(0.0, 0.01, pd - 0.006));
  }

  // ray origin dot
  float roDist = length(uv - ro);
  col = mix(col, vec3(1.0), 1.0 - smoothstep(0.0, 0.018, roDist - 0.013));
  col = mix(col, vec3(0.3, 1.0, 0.5), 1.0 - smoothstep(0.0, 0.015, roDist - 0.009));

  col = pow(col, vec3(0.4545));
  fragColor = vec4(col, 1.0);
}
