#version 410

uniform vec2 u_resolution; // viewport size in pixels (width, height)
uniform int u_frame; // frame increment counter
uniform vec2 u_mouse;
uniform vec2 u_cameraRot;
uniform vec3 u_cameraPos;
uniform float u_time;
uniform vec3 u_tempColor;

uniform sampler2D u_pass1;

uniform sampler2D u_main;
uniform int u_spf; //16, [1, 64]
out vec4 fragColor;

// a pixel value multiplier of light before tone mapping and sRGB
const float c_exposure = 0.5f;
const float KEY_SPACE = 32.5 / 256.0;
const float c_rayPosNormalNudge = 0.01f;

vec3 LessThan(vec3 f, float value)
{
    return vec3(
        (f.x < value) ? 1.0f : 0.0f,
        (f.y < value) ? 1.0f : 0.0f,
        (f.z < value) ? 1.0f : 0.0f);
}

vec3 LinearToSRGB(vec3 rgb)
{
    rgb = clamp(rgb, 0.0f, 1.0f);

    return mix(
        pow(rgb, vec3(1.0f / 2.4f)) * 1.055f - 0.055f,
        rgb * 12.92f,
        LessThan(rgb, 0.0031308f)
    );
}

vec3 SRGBToLinear(vec3 rgb)
{
    rgb = clamp(rgb, 0.0f, 1.0f);

    return mix(
        pow(((rgb + 0.055f) / 1.055f), vec3(2.4f)),
        rgb / 12.92f,
        LessThan(rgb, 0.04045f)
    );
}

// ACES tone mapping curve fit to go from HDR to LDR
//https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
vec3 ACESFilm(vec3 x)
{
    float a = 2.51f;
    float b = 0.03f;
    float c = 2.43f;
    float d = 0.59f;
    float e = 0.14f;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0f, 1.0f);
}

float FresnelReflectAmount(float n1, float n2, vec3 normal, vec3 incident, float f0, float f90)
{
    // Schlick aproximation
    float r0 = (n1 - n2) / (n1 + n2);
    r0 *= r0;
    float cosX = -dot(normal, incident);
    if (n1 > n2)
    {
        float n = n1 / n2;
        float sinT2 = n * n * (1.0 - cosX * cosX);
        // Total internal reflection
        if (sinT2 > 1.0)
            return f90;
        cosX = sqrt(1.0 - sinT2);
    }
    float x = 1.0 - cosX;
    float ret = r0 + (1.0 - r0) * x * x * x * x * x;

    // adjust reflect multiplier for object reflectivity
    return mix(f0, f90, ret);
}

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
    // Note: diffuse chance is 1.0f - (specularChance+refractionChance)
    vec3 albedo; // the color used for diffuse lighting
    vec3 emissive; // how much the surface glows
    float specularChance; // percentage chance of doing a specular reflection
    float specularRoughness; // how rough the specular reflections are
    vec3 specularColor; // the color tint of specular reflections
    float IOR; // index of refraction. used by fresnel and refraction.
    float refractionChance; // percent chance of doing a refractive transmission
    float refractionRoughness; // how rough the refractive transmissions are
    vec3 refractionColor; // absorption for beer's law
};

struct SDF {
    float distance;
    float id;
};

struct SRayHitInfo
{
    bool fromInside;
    float dist;
    vec3 normal;
    Material material;
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

float dot2(vec3 v) {
    return dot(v, v);
}

float sdSphere(vec3 p, float r)
{
    return length(p) - r;
}

uint wang_hash(inout uint seed)
{
    seed = uint(seed ^ uint(61)) ^ uint(seed >> uint(16));
    seed *= uint(9);
    seed = seed ^ (seed >> 4);
    seed *= uint(0x27d4eb2d);
    seed = seed ^ (seed >> 15);
    return seed;
}

float RandomFloat01(inout uint state)
{
    return float(wang_hash(state)) / 4294967296.0;
}

vec3 RandomUnitVector(inout uint state)
{
    float z = RandomFloat01(state) * 2.0f - 1.0f;
    float a = RandomFloat01(state) * c_twopi;
    float r = sqrt(1.0f - z * z);
    float x = r * cos(a);
    float y = r * sin(a);
    return vec3(x, y, z);
}

float sdPlane(vec3 p, vec3 n, float h)
{
    // n must be normalized
    return dot(p, n) + h;
}

float sdBox(vec3 p, vec3 b)
{
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

Material GetZeroedMaterial()
{
    Material ret;
    ret.albedo = vec3(0.0f, 0.0f, 0.0f);
    ret.emissive = vec3(0.0f, 0.0f, 0.0f);
    ret.specularChance = 0.0f;
    ret.specularRoughness = 0.0f;
    ret.specularColor = vec3(0.0f, 0.0f, 0.0f);
    ret.IOR = 1.0f;
    ret.refractionChance = 0.0f;
    ret.refractionRoughness = 0.0f;
    ret.refractionColor = vec3(0.0f, 0.0f, 0.0f);
    return ret;
}

SDF map(vec3 p) {
    SDF sphere1;
    sphere1.distance = sdSphere(p - vec3(0.3, -0.3, 0.0), 0.1);
    sphere1.id = 8.0;

    SDF sphere2;
    sphere2.distance = sdSphere(p - vec3(0.0, -0.3, 0.0), 0.1);
    sphere2.id = 7.0;
    SDF sphere3;
    sphere3.distance = sdSphere(p - vec3(-0.3, -0.3, 0.0), 0.1);
    sphere3.id = 2.0;

    SDF sun;
    sun.distance = sdBox(p - vec3(0.0, 0.5, 0.5), vec3(0.2, 0.01, 0.2));
    sun.id = 0.0;

    SDF ground;
    ground.distance = sdPlane(p, vec3(0.0, 1.0, 0.0), 0.4);
    ground.id = 4.0;

    SDF back;
    back.distance = sdPlane(p, vec3(0.0, 0.0, 1.0), 0.5);
    back.id = 4.0;

    SDF left;
    left.distance = sdPlane(p, vec3(1.0, 0.0, 0.0), 0.5);
    left.id = 5.0;

    SDF right;
    right.distance = sdPlane(p, vec3(-1.0, 0.0, 0.0), 0.5);
    right.id = 6.0;

    SDF top;
    top.distance = sdPlane(p, vec3(0.0, -1.0, 0.0), 0.51);
    top.id = 4.0; // white

    SDF behind;
    behind.distance = sdPlane(p, vec3(0.0, 0.0, -1.0), 1.5);
    behind.id = 4.0;

    SDF result = opUnionID(sphere1, sphere2);
    result = opUnionID(result, sphere3);
    result = opUnionID(result, ground);
    result = opUnionID(result, back);
    result = opUnionID(result, left);
    result = opUnionID(result, right);
    result = opUnionID(result, top);
    result = opUnionID(result, behind);

    result = opUnionID(result, sun);

    return result;
}

vec3 getNormal(vec3 p) {
    vec2 e = vec2(EPSILON, 0.0);
    return normalize(vec3(
            map(p + e.xyy).distance - map(p - e.xyy).distance,
            map(p + e.yxy).distance - map(p - e.yxy).distance,
            map(p + e.yyx).distance - map(p - e.yyx).distance
        ));
}

SDF rayMarch(vec3 ro, vec3 rd) {
    SDF hit, object;
    float t = 0.0;
    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * t;
        hit = map(p); // Distance to nearest object
        //really need to understand why mult this by 0.98 fixes the pattern
        t += abs(hit.distance) * 0.98;
        object.distance = hit.distance;
        object.id = hit.id;
        if (abs(hit.distance) < EPSILON || t > MAX_DIST) break;
    }
    object.distance = t;
    object.id = hit.id;
    return object;
}

Material getMaterial(SDF object, vec3 p) {
    Material material = GetZeroedMaterial();
    switch (int(object.id)) {
        //white light
        case 0:
        // material.emissive = vec3(1, 0.7529422167760779, 0.5775804404296506) * 20.0f;
        // material.emissive = vec3(1.0) * 20.0f;
        vec3 color = SRGBToLinear(u_tempColor);
        material.emissive = color * 20.0f;
        material.albedo = vec3(0);
        break;
        //
        case 1:
        material.emissive = vec3(0.0, 0.0, 0.0);
        material.albedo = vec3(0.1, 0.7, 0.1);
        break;
        //white
        case 2:
        material.emissive = vec3(0.0, 0.0, 0.0);
        material.albedo = vec3(0.7, 0.7, 0.7);
        break;
        //red
        case 3:
        material.emissive = vec3(0.0, 0.0, 0.0);
        material.albedo = vec3(0.7, 0.1, 0.1);
        break;
        //back wall
        case 4:
        material.emissive = vec3(0.0, 0.0, 0.0);
        float stripe = mod(floor(p.x * 20.0), 2.0);
        material.albedo = mix(vec3(0.7f, 0.7f, 0.7f), vec3(0.2f, 0.2f, 0.2f), stripe);
        // material.albedo = vec3(0.7, 0.7, 0.7);
        break;
        //left wall
        case 5:
        material.emissive = vec3(0.0, 0.0, 0.0);
        material.albedo = vec3(0.7f, 0.1f, 0.1f);
        break;
        //right wall
        case 6:
        material.emissive = vec3(0.0, 0.0, 0.0);
        material.albedo = vec3(0.1f, 0.7f, 0.1f);
        break;
        case 7:
        material.albedo = vec3(1.0f, 1.0f, 1.0f);
        material.emissive = vec3(0.0f, 0.0f, 0.0f);
        material.specularChance = 1.0f;
        material.specularRoughness = 0.25f;
        material.specularColor = vec3(1.0f, 1.0f, 1.0f);
        break;
        case 8:
        material = GetZeroedMaterial();
        material.albedo = vec3(0.9f, 0.25f, 0.25f);
        material.emissive = vec3(0.0f, 0.0f, 0.0f);
        material.specularChance = 0.02f;
        material.specularRoughness = 0.0f;
        material.specularColor = vec3(1.0f, 1.0f, 1.0f) * 0.8f;
        material.IOR = 1.5f;
        material.refractionChance = 1.0f;
        material.refractionRoughness = 0.0f;
        break;
        default:
        material.albedo = vec3(1.0, 0.0, 1.0); // bright magenta for unhandled ids
        break;
    }
    return material;
}

void getCurrentHit(vec3 rayOrigin, vec3 rayDirection, inout SRayHitInfo hitInfo) {
    SDF object = rayMarch(rayOrigin, rayDirection);
    if (object.distance < MAX_DIST) {
        hitInfo.dist = object.distance;
        hitInfo.normal = getNormal(rayOrigin + rayDirection * object.distance);
        hitInfo.material = getMaterial(object, rayOrigin + rayDirection * object.distance);

        if (dot(rayDirection, hitInfo.normal) > 0.0) {
            hitInfo.normal = -hitInfo.normal;
            hitInfo.fromInside = true;
        }
    } else {
        hitInfo.dist = c_superFar;
    }
}

vec3 getColorForRay(in vec3 startRayPos, in vec3 startRayDir, inout uint rngState)
{
    // initialize
    vec3 ret = vec3(0.0f, 0.0f, 0.0f);
    vec3 throughput = vec3(1.0f, 1.0f, 1.0f);
    vec3 rayPos = startRayPos;
    vec3 rayDir = startRayDir;

    for (int bounceIndex = 0; bounceIndex <= c_numBounces; ++bounceIndex)
    {
        // shoot a ray out into the world
        SRayHitInfo hitInfo;
        hitInfo.material = GetZeroedMaterial();
        hitInfo.dist = c_superFar;
        hitInfo.fromInside = false;
        getCurrentHit(rayPos, rayDir, hitInfo);

        // if the ray missed, we are done
        if (hitInfo.dist == c_superFar)
        {
            break;
        }

        // do absorption if we are hitting from inside the object
        if (hitInfo.fromInside)
            throughput *= exp(-hitInfo.material.refractionColor * hitInfo.dist);

        // get the pre-fresnel chances
        float specularChance = hitInfo.material.specularChance;
        float refractionChance = hitInfo.material.refractionChance;
        //float diffuseChance = max(0.0f, 1.0f - (refractionChance + specularChance));

        // take fresnel into account for specularChance and adjust other chances.
        // specular takes priority.
        // chanceMultiplier makes sure we keep diffuse / refraction ratio the same.
        float rayProbability = 1.0f;
        if (specularChance > 0.0f)
        {
            specularChance = FresnelReflectAmount(
                    hitInfo.fromInside ? hitInfo.material.IOR : 1.0,
                    !hitInfo.fromInside ? hitInfo.material.IOR : 1.0,
                    rayDir, hitInfo.normal, hitInfo.material.specularChance, 1.0f);

            float chanceMultiplier = (1.0f - specularChance) / (1.0f - hitInfo.material.specularChance);
            refractionChance *= chanceMultiplier;
            //diffuseChance *= chanceMultiplier;
        }

        // calculate whether we are going to do a diffuse, specular, or refractive ray
        float doSpecular = 0.0f;
        float doRefraction = 0.0f;
        float raySelectRoll = RandomFloat01(rngState);
        if (specularChance > 0.0f && raySelectRoll < specularChance)
        {
            doSpecular = 1.0f;
            rayProbability = specularChance;
        }
        else if (refractionChance > 0.0f && raySelectRoll < specularChance + refractionChance)
        {
            doRefraction = 1.0f;
            rayProbability = refractionChance;
        }
        else
        {
            rayProbability = 1.0f - (specularChance + refractionChance);
        }

        // numerical problems can cause rayProbability to become small enough to cause a divide by zero.
        rayProbability = max(rayProbability, 0.001f);

        // update the ray position
        if (doRefraction == 1.0f)
        {
            rayPos = (rayPos + rayDir * hitInfo.dist) - hitInfo.normal * c_rayPosNormalNudge;
        }
        else
        {
            rayPos = (rayPos + rayDir * hitInfo.dist) + hitInfo.normal * c_rayPosNormalNudge;
        }

        // Calculate a new ray direction.
        // Diffuse uses a normal oriented cosine weighted hemisphere sample.
        // Perfectly smooth specular uses the reflection ray.
        // Rough (glossy) specular lerps from the smooth specular to the rough diffuse by the material roughness squared
        // Squaring the roughness is just a convention to make roughness feel more linear perceptually.
        vec3 diffuseRayDir = normalize(hitInfo.normal + RandomUnitVector(rngState));

        vec3 specularRayDir = reflect(rayDir, hitInfo.normal);
        specularRayDir = normalize(mix(specularRayDir, diffuseRayDir, hitInfo.material.specularRoughness * hitInfo.material.specularRoughness));

        vec3 refractionRayDir = refract(rayDir, hitInfo.normal, hitInfo.fromInside ? hitInfo.material.IOR : 1.0f / hitInfo.material.IOR);
        refractionRayDir = normalize(mix(refractionRayDir, normalize(-hitInfo.normal + RandomUnitVector(rngState)), hitInfo.material.refractionRoughness * hitInfo.material.refractionRoughness));

        rayDir = mix(diffuseRayDir, specularRayDir, doSpecular);
        rayDir = mix(rayDir, refractionRayDir, doRefraction);

        // add in emissive lighting
        ret += hitInfo.material.emissive * throughput;

        // update the colorMultiplier. refraction doesn't alter the color until we hit the next thing, so we can do light absorption over distance.
        if (doRefraction == 0.0f)
            throughput *= mix(hitInfo.material.albedo, hitInfo.material.specularColor, doSpecular);

        // since we chose randomly between diffuse, specular, refract,
        // we need to account for the times we didn't do one or the other.
        throughput /= rayProbability;

        // Russian Roulette
        // As the throughput gets smaller, the ray is more likely to get terminated early.
        // Survivors have their value boosted to make up for fewer samples being in the average.
        {
            float p = max(throughput.r, max(throughput.g, throughput.b));
            if (RandomFloat01(rngState) > p)
                break;

            // Add the energy we 'lose' by randomly terminating paths
            throughput *= 1.0f / p;
        }
    }

    // return pixel color
    return ret;
}

void pR(inout vec2 p, float a) {
    p = cos(a) * p + sin(a) * vec2(p.y, -p.x);
}

mat3 getCam(vec3 ro, vec3 lookAt) {
    vec3 camF = normalize(vec3(lookAt - ro));
    vec3 camR = normalize(cross(vec3(0, 1, 0), camF));
    vec3 camU = cross(camF, camR);
    return mat3(camR, camU, camF);
}

void applyRotation(inout vec3 ro) {
    // Pitch (up/down) around the XZ plane
    pR(ro.yz, u_cameraRot.y);
    // Yaw (left/right) around the vertical axis
    pR(ro.xz, u_cameraRot.x);
}

void main()
{
    //RNG setup
    uint state = uint(uint(gl_FragCoord.x) * uint(1973) + uint(gl_FragCoord.y) * uint(9277) + uint(u_frame) * uint(26699)) | uint(1);
    vec3 accumulated_color = vec3(0.0);
    int samples_per_frame = u_spf;

    for (int i = 0; i < samples_per_frame; i++) {
        vec2 jitter = vec2(RandomFloat01(state), RandomFloat01(state)) - 0.5;
        vec2 uv = (gl_FragCoord.xy + jitter) / u_resolution.xy;
        vec2 pixelTarget2D = (uv * 2.0f) - 1.0f;
        float aspectRatio = u_resolution.x / u_resolution.y;

        // calculate the camera distance
        float cameraDistance = 1.0f / tan(c_FOVDegrees * 0.5f * c_pi / 180.0f);

        Ray ray;
        // 1. The origin is strictly controlled by WASD
        ray.origin = u_cameraPos;

        // 2. Base ray direction (pointing down the -Z axis like a standard camera)
        vec3 rayDir = normalize(vec3(pixelTarget2D.x * aspectRatio, pixelTarget2D.y, -cameraDistance));

        // 3. Rotate the ray itself based on mouse movement
        pR(rayDir.yz, u_cameraRot.y); // Pitch up/down
        pR(rayDir.xz, u_cameraRot.x); // Yaw left/right

        ray.direction = rayDir;

        accumulated_color += getColorForRay(ray.origin, ray.direction, state);
    }

    vec3 current_average = accumulated_color / float(samples_per_frame);

    // average the frames together
    vec4 lastFrameColor = texture(u_pass1, gl_FragCoord.xy / u_resolution.xy);

    // NEW MATH:
    // We need to tell the blend that we just added 64 samples, not 1.
    // If we use u_frame, it's much safer:
    float blend = 1.0 / float(u_frame + 1);

    vec3 color = mix(lastFrameColor.rgb, current_average, blend);

    // show the result - use a solid 1.0 for Alpha so Main pass can see it!
    fragColor = vec4(color, 1.0);
}
