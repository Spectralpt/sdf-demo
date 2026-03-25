#version 410 core

layout(location = 0) out vec4 fragColor;

uniform vec2 u_resolution;
uniform vec2 u_mouse;

const float FOV = 1.0;
const int MAX_STEPS = 256;
const float MAX_DIST = 500;
const float EPSILON = 0.001;

#define PI 3.14159265
#define TAU (2*PI)

void pR(inout vec2 p, float a) {
  p = cos(a) * p + sin(a) * vec2(p.y, -p.x);
}

vec2 fOpUnionID(vec2 res1, vec2 res2) {
  return (res1.x < res2.x) ? res1 : res2;
}

// IQ primitives
float sdRoundBox(vec3 p, vec3 b, float r) {
  vec3 d = abs(p) - b;
  return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0) - r;
}
float sdPlane(vec3 p, vec3 n, float h) {
  return dot(p, n) + h;
}

float sdSphere(vec3 p, float r) {
  return length(p) - r;
}

float sdBox(vec3 p, vec3 b) {
  vec3 d = abs(p) - b;
  return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}

float sdCylinder(vec3 p, float r, float h) {
  vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(r, h);
  return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdTorus(vec3 p, vec2 t) {
  vec2 q = vec2(length(p.xz) - t.x, p.y);
  return length(q) - t.y;
}

float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
  vec3 pa = p - a, ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h) - r;
}
vec2 map(vec3 p) {
  // floor
  vec2 res = vec2(sdPlane(p, vec3(0, 1, 0), 0.0), 1.0);

  // large sphere center
  res = fOpUnionID(res, vec2(sdSphere(p - vec3(0, 1, 0), 1.0), 2.0));

  // small sphere left
  res = fOpUnionID(res, vec2(sdSphere(p - vec3(-2.5, 0.35, 0), 0.35), 3.0));

  // box right
  res = fOpUnionID(res, vec2(sdBox(p - vec3(2, 0.5, 0), vec3(0.5)), 4.0));

  // rounded box back left
  res = fOpUnionID(res, vec2(sdRoundBox(p - vec3(-2, 0.5, -1.5), vec3(0.5), 0.15), 5.0));

  // torus flat on ground
  res = fOpUnionID(res, vec2(sdTorus(p - vec3(0, 0.0, -2.5), vec2(0.6, 0.2)), 6.0));

  // tall thin capsule far right
  res = fOpUnionID(res, vec2(sdCapsule(p, vec3(3.5, 0, -1), vec3(3.5, 1.5, -1), 0.25), 7.0));

  return res;
}

vec3 getNormal(vec3 p) {
  vec2 e = vec2(EPSILON, 0.0);
  vec3 n = vec3(map(p).x) - vec3(map(p - e.xyy).x, map(p - e.yxy).x, map(p - e.yyx).x);
  return normalize(n);
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

vec3 getMaterial(vec3 p, float id, vec3 normal) {
  switch (int(id)) {
    case 1:
    return vec3(0.2 + 0.4 * mod(floor(p.x) + floor(p.z), 2.0)); // checker floor
    case 2:
    return vec3(0.4, 0.8, 1.0); // large sphere - blue
    case 3:
    return vec3(0.9, 0.6, 0.2); // small sphere - orange
    case 4:
    return vec3(0.8, 0.8, 0.8); // box - white
    case 5:
    return vec3(0.2, 0.9, 0.4); // rounded box - green
    case 6:
    return vec3(0.9, 0.2, 0.2); // torus - red
    case 7:
    return vec3(0.8, 0.6, 0.9); // capsule - lavender
  }
  return vec3(0.4);
}
float getSoftShadow(vec3 p, vec3 lightPos) {
  float res = 1.0;
  float dist = 0.01;
  float lightSize = 0.03;
  for (int i = 0; i < MAX_STEPS; i++) {
    float hit = map(p + lightPos * dist).x;
    res = min(res, hit / (dist * lightSize));
    dist += hit;
    if (hit < 0.0001 || dist > 60.0) break;
  }
  return clamp(res, 0.0, 1.0);
}

float getAmbientOcclusion(vec3 p, vec3 normal) {
  float occ = 0.0;
  float weight = 1.0;
  for (int i = 0; i < 8; i++) {
    float len = 0.01 + 0.02 * float(i * i);
    float dist = map(p + normal * len).x;
    occ += (len - dist) * weight;
    weight *= 0.85;
  }
  return 1.0 - clamp(0.6 * occ, 0.0, 1.0);
}

vec3 getLight(vec3 p, vec3 rd, float id) {
  vec3 lightPos = vec3(20.0, 40.0, -30.0);
  vec3 L = normalize(lightPos - p);
  vec3 N = getNormal(p);
  vec3 V = -rd;
  vec3 R = reflect(-L, N);

  vec3 color = getMaterial(p, id, N);

  vec3 specColor = vec3(0.5);
  vec3 specular = specColor * pow(clamp(dot(R, V), 0.0, 1.0), 10.0);
  vec3 diffuse = color * clamp(dot(L, N), 0.0, 1.0);
  vec3 ambient = color * 0.05;
  vec3 fresnel = 0.25 * color * pow(1.0 + dot(rd, N), 3.0);

  float shadow = getSoftShadow(p + N * 0.02, normalize(lightPos));
  float occ = getAmbientOcclusion(p, N);
  return (ambient + fresnel) * occ + (specular * occ + diffuse) * shadow;
}

mat3 getCam(vec3 ro, vec3 lookAt) {
  vec3 camF = normalize(vec3(lookAt - ro));
  vec3 camR = normalize(cross(vec3(0, 1, 0), camF));
  vec3 camU = cross(camF, camR);
  return mat3(camR, camU, camF);
}

void mouseControl(inout vec3 ro) {
  vec2 m = u_mouse / u_resolution;
  pR(ro.yz, m.y * PI * 0.4 - 0.4);
  pR(ro.xz, m.x * TAU);
}

vec3 render(vec2 uv) {
  vec3 col = vec3(0);
  vec3 background = vec3(0.5, 0.8, 0.9);

  vec3 ro = vec3(-5.0, 5.0, -5.0);
  mouseControl(ro);

  vec3 lookAt = vec3(0, 2, 0);
  vec3 rd = getCam(ro, lookAt) * normalize(vec3(uv, FOV));

  vec2 object = rayMarch(ro, rd);

  if (object.x < MAX_DIST) {
    vec3 p = ro + object.x * rd;
    col += getLight(p, rd, object.y);
    col = mix(col, background, 1.0 - exp(-0.00002 * object.x * object.x));
  } else {
    col += background - max(0.9 * rd.y, 0.0);
  }
  return col;
}

vec2 getUV(vec2 offset) {
  return (2.0 * (gl_FragCoord.xy + offset) - u_resolution.xy) / u_resolution.y;
}

vec3 renderAAx4() {
  vec4 e = vec4(0.125, -0.125, 0.375, -0.375);
  vec3 colAA = render(getUV(e.xz)) + render(getUV(e.yw)) + render(getUV(e.wx)) + render(getUV(e.zy));
  return colAA /= 4.0;
}

void main() {
  vec3 col = renderAAx4();
  col = pow(col, vec3(0.4545));
  fragColor = vec4(col, 1.0);
}
