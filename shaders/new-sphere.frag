const int MAX_STEPS = 256;
const float EPSILON = 0.001;
const float MAX_DIST = 500.0;
const float c_FOVDegrees = 90.0f;
const float c_pi = 3.14159265359f;
const float c_twopi = 2.0f * c_pi;
// the farthest we look for path tracing ray hits
const float c_superFar = 10000.0f;
const int c_numBounces = 8;

struct Ray {
    vec3 origin;
    vec3 direction;
    vec3 target;
};

struct Material {
    vec3 emissive;
    vec3 albedo;
};

struct SDF {
    float distance;
    float id;
};

struct SRayHitInfo
{
    float dist;
    vec3 normal;
    vec3 albedo;
    vec3 emissive;
};

float opUnion(float a, float b)
{
    return min(a, b);
}

SDF opUnionID(SDF res1, SDF res2) {
    if (res1.distance < res2.distance) {
        return res1;
    } else {
        return res2;
    }
}

// PCG (permuted congruential generator). Thanks to:
// www.pcg-random.org and www.shadertoy.com/view/XlGcRh
uint NextRandom(inout uint state)
{
    state = state * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    uint result = (word >> 22u) ^ word;
    return result;
}

float RandomValue(inout uint state)
{
    return float(NextRandom(state)) / 4294967295.0; // 2^32 - 1
}

// Random value in normal distribution (with mean=0 and sd=1)
float RandomValueNormalDistribution(inout uint state)
{
    float u1 = RandomValue(state);
    float u2 = RandomValue(state);

    // Safeguard against log(0) which is undefined/infinity
    // We use a tiny offset (epsilon)
    u1 = max(u1, 1e-7);

    float theta = 2.0 * 3.14159265359 * u2;
    float rho = sqrt(-2.0 * log(u1));
    return rho * cos(theta);
}

// Calculate a random direction
vec3 RandomDirection(inout uint state)
{
    // Thanks to https://math.stackexchange.com/a/1585996
    float x = RandomValueNormalDistribution(state);
    float y = RandomValueNormalDistribution(state);
    float z = RandomValueNormalDistribution(state);
    return normalize(vec3(x, y, z));
}

float sdSphere(vec3 p, float r)
{
    return length(p) - r;
}

float sdPlane(vec3 p, vec3 n, float h)
{
    // n must be normalized
    return dot(p, n) + h;
}

SDF map(vec3 p) {
    SDF sphere1;
    sphere1.distance = sdSphere(p - vec3(0.5, 0.0, 0.0), 0.1);
    sphere1.id = 1.0;

    SDF sphere2;
    sphere2.distance = sdSphere(p - vec3(0.0, 0.0, 0.0), 0.1);
    sphere2.id = 2.0;
    SDF sphere3;
    sphere3.distance = sdSphere(p - vec3(-0.5, 0.0, -1.0), 0.1);
    sphere3.id = 3.0;

    SDF sun;
    sun.distance = sdSphere(p - vec3(1.0, 1.0, 2.0), 1.0);
    sun.id = 0.0;

    SDF result = opUnionID(sphere1, sphere2);
    result = opUnionID(result, sphere3);
    result = opUnionID(result, sun);

    return result;
}

vec3 getNormal(vec3 p) {
    vec2 e = vec2(EPSILON, 0.0);
    vec3 n = vec3(map(p).distance) - vec3(
                map(p - e.xyy).distance,
                map(p - e.yxy).distance,
                map(p - e.yyx).distance
            );
    return normalize(n);
}

SDF rayMarch(vec3 ro, vec3 rd) {
    SDF hit, object;
    float t = 0.0;
    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * t;
        hit = map(p); // Distance to nearest object
        t += hit.distance;
        object.distance = hit.distance;
        object.id = hit.id;
        if (abs(hit.distance) < EPSILON || t > MAX_DIST) break;
    }
    object.distance = t;
    object.id = hit.id;
    return object;
}

Material getMaterial(SDF object) {
    Material material;
    switch (int(object.id)) {
        case 0:
        material.emissive = vec3(1) * 20.0f;
        material.albedo = vec3(0);
        break;
        case 1:
        material.emissive = vec3(0.0, 0.0, 0.0);
        material.albedo = vec3(0.1, 0.7, 0.1);
        break;
        case 2:
        material.emissive = vec3(0.0, 0.0, 0.0);
        material.albedo = vec3(0.7, 0.7, 0.7);
        break;
        case 3:
        material.emissive = vec3(0.0, 0.0, 0.0);
        material.albedo = vec3(0.7, 0.1, 0.1);
        break;
    }
    return material;
}

void getCurrentHit(vec3 rayOrigin, vec3 rayDirection, inout SRayHitInfo hitInfo) {
    SDF object = rayMarch(rayOrigin, rayDirection);
    if (object.distance < MAX_DIST) {
        hitInfo.dist = object.distance;
        hitInfo.normal = getNormal(rayOrigin + rayDirection * object.distance);

        Material mat = getMaterial(object);
        hitInfo.albedo = mat.albedo;
        hitInfo.emissive = mat.emissive;
    }
}

vec3 getColorForRay(vec3 startRayPosition, vec3 startRayDirection, inout uint state) {
    // initialize
    vec3 ret = vec3(0.0f, 0.0f, 0.0f);
    vec3 throughput = vec3(1.0f, 1.0f, 1.0f);
    vec3 rayPos = startRayPosition;
    vec3 rayDir = startRayDirection;

    for (int bounceIndex = 0; bounceIndex <= c_numBounces; ++bounceIndex) {
        SRayHitInfo hitInfo;
        hitInfo.dist = c_superFar;
        getCurrentHit(rayPos, rayDir, hitInfo);

        if (hitInfo.dist == c_superFar) {
            vec3 sky = mix(vec3(0.1, 0.1, 0.1), vec3(0.3, 0.4, 0.6), rayDir.y * 0.5 + 0.5);
            ret += sky * throughput;
            break;
        }

        // Progress the ray (current position plus the direction we want to go * the distance we need to go)
        // we also nudge the hit by epsilon along the normal so it doesnt accidentaly get stuck
        // not sure if we need to do this since we already do it while raymarching upper in the chain
        rayPos = (rayPos + rayDir * hitInfo.dist) + hitInfo.normal * EPSILON;
        // cosine weighted sample
        rayDir = normalize(hitInfo.normal + RandomDirection(state));

        ret += hitInfo.emissive * throughput;
        throughput *= hitInfo.albedo;
    }
    return ret;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    //RNG setup
    uint state = uint(uint(fragCoord.x) * uint(1973) + uint(fragCoord.y) * uint(9277) + uint(iFrame) * uint(26699)) | uint(1);

    vec2 uv = fragCoord / iResolution.xy;
    vec2 pixelTarget2D = (uv * 2.0f) - 1.0f;
    float aspectRatio = iResolution.x / iResolution.y;

    // calculate the camera distance
    float cameraDistance = 1.0f / tan(c_FOVDegrees * 0.5f * c_pi / 180.0f);

    Ray ray;
    ray.origin = vec3(0.0, 0.0, 5.0);
    ray.target = vec3(pixelTarget2D, cameraDistance);
    //Q:why does the y axis need to be corrected for the aspect ratio?
    //A:because of the uv coordinate system, it goes from -1 to 1 so its a square, the screen is not a square
    ray.target.y /= aspectRatio;
    ray.direction = normalize(ray.target - ray.origin);

    vec3 color = getColorForRay(ray.origin, ray.direction, state);

    // average the frames together
    vec3 lastFrameColor = texture(iChannel0, fragCoord / iResolution.xy).rgb;
    color = mix(lastFrameColor, color, 1.0f / float(iFrame + 1));

    fragColor = vec4(color, 1.0f);
}
