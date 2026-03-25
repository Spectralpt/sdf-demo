#version 410

layout(location = 0) out vec4 fragColor;

uniform vec2 u_resolution;

const float FOV = 1.0;
const int MAX_STEPS = 256;
const float MAX_DIST = 500;
const float EPSILON = 0.001;

float sdSphere(vec3 p, float r)
{
  return length(p) - r;
}

vec2 rayMarch(vec3 ro, vec3 rd) {
  vec2 hit, object;
  for (int i = 0; i < MAX_STEPS; i++) {
    vec3 p = ro + object.x * rd;
    hit = map(p);
    object.x += hit.x;
    object.y = hit.y;
    if (abs(hit.x) < EPSILON || object.x > MAX_DIST) break;
  }
  return object;
}
