#version 460 core

uniform float runtime;
uniform uint  runframe;
uniform vec2  resolution;

uniform vec3  camera_pos;
uniform vec3  camera_z;
uniform vec3  camera_y;
uniform bool  reset;

uniform sampler2D last_frame;
uniform sampler2D block_textures;
uniform sampler2D environment_texture;

in vec2 fragCoord;
in vec2 fragTexCoord;

out vec4 fragColor;

// DEFINITIONS ---------------------------------------------------------------------------------------

#define TWO_PI      6.28318530718
#define PI          3.14159265359
#define DEG_RAD     0.01745329252
#define M_E         2.71828182846

#define HDRI_STRENGTH 0.5

#define MAX_DIST      5000.0
#define RAY_BOUNCES   6
#define SPP           1
#define SAMPLES       32

#define EPSILON       0.001

// CONSTANTS ---------------------------------------------------------------------------------------

// GLOBALS ---------------------------------------------------------------------------------------

uvec4 white_noise_seed;
uvec2 pixel;
vec3  rgb_noise;

// GENERIC FUNCTIONS ---------------------------------------------------------------------------------------

float cross2d( in vec2 a, in vec2 b ) { return a.x * b.y - a.y * b.x; }
vec4 conjugate(vec4 q) { return vec4(-q.x, -q.y, -q.z, q.w); }
float mapFloat(float FromMin, float FromMax, float ToMin, float ToMax, float Value) {
	if (Value > FromMax) return ToMax;
	else if (Value < FromMin) return ToMin;
	else return (ToMin + ((ToMax - ToMin) / (FromMax - FromMin)) * (Value - FromMin));
}

uvec4 hash(uvec4 seed) {
	seed = seed * 1664525u + 1013904223u;
	seed.x += seed.y*seed.w; seed.y += seed.z*seed.x; seed.z += seed.x*seed.y; seed.w += seed.y*seed.z;
	seed = seed ^ (seed>>16u);
	seed.x += seed.y*seed.w; seed.y += seed.z*seed.x; seed.z += seed.x*seed.y; seed.w += seed.y*seed.z;
	return seed;
}
float rand1() { return float(hash(white_noise_seed).x)   / float(0xffffffffu); }
float rand1r(float min_x, float max_x) { return mapFloat(0.0, 1.0, min_x, max_x, float(hash(white_noise_seed).x)   / float(0xffffffffu)); }
vec2  rand2() { return vec2 (hash(white_noise_seed).xy)  / float(0xffffffffu); }
vec3  rand3() { return vec3 (hash(white_noise_seed).xyz) / float(0xffffffffu); }
vec4  rand4() { return vec4 (hash(white_noise_seed))     / float(0xffffffffu); }
vec2 normaland2(float sigma, vec2 mean) {
	vec2 Z = rand2();
	return mean + sigma * sqrt(-2.0 * log(Z.x)) * vec2(cos(TWO_PI * Z.y), sin(TWO_PI * Z.y));
}
vec3 normaland3(float sigma, vec3 mean) {
	vec4 Z = rand4();
	return mean + sigma * sqrt(-2.0 * log(Z.xxy)) * vec3(cos(TWO_PI * Z.z), sin(TWO_PI * Z.z), cos(TWO_PI * Z.w));
}
void rng_initialize(vec2 pix, uint frame) {
	pixel = uvec2(pix);
	white_noise_seed = uvec4(pixel, frame, uint(pixel.x) + uint(pixel.y));
}

float snell (float sin_theta, float iori, float iort) {
	return iori / iort * sin_theta;
}
float fresnel(float iori, float iort, float cosi, float cost){
	float rpar = (iort * cosi - iori * cost) / (iort * cosi + iori * cost);
	float rper = (iori * cosi - iort * cost) / (iori * cosi + iort * cost);
	rpar *= rpar;
	rper *= rper;
	return (rpar + rper) / 2.;
}

mat3 eulerToRot(vec3 euler) {
	const float Yaw =   euler.x * DEG_RAD;
	const float Pitch = euler.y * DEG_RAD;
	const float Roll =  euler.z * DEG_RAD;

	const mat3 yawMat = mat3 (
		 cos(Yaw) , 0 , sin(Yaw) ,
		 0        , 1 , 0        ,
		-sin(Yaw) , 0 , cos(Yaw)
	);

	const mat3 pitchMat = mat3 (
		1 , 0          ,  0          ,
		0 , cos(Pitch) , -sin(Pitch) ,
		0 , sin(Pitch) ,  cos(Pitch)
	);

	const mat3 rollMat = mat3 (
		cos(Roll) , -sin(Roll) , 0 ,
		sin(Roll) ,  cos(Roll) , 0 ,
		0         ,  0         , 1
	);

	return pitchMat * yawMat * rollMat;
}

// STRUCTS ---------------------------------------------------------------------------------------
struct Ray {
	vec3  Ray_Origin;
	vec3  Ray_Direction;
};
struct Hit {
	float Ray_Length;
	vec3  Hit_New_Dir;
	vec3  Hit_Pos;
	int   Hit_Obj;
	bool  Ray_Inside;
	int   Hit_Mat;
	vec2  Hit_UV;
};
struct Cube {
	vec3 Position;
	int  Mat;
};
struct Box{
	vec3 Position;
	vec3 Size;
	int  Mat;
};
struct Sphere {
	vec3  Position;
	float Diameter;
	int   Mat;
};

// SCENE ---------------------------------------------------------------------------------------
#define SEA_LANTERN       1
#define PRISMARINE_BRICKS 2
#define MAGMA_BLOCK       3
#define GRAVEL            4
#define GOLD              5
#define DARK_PRISMARINE   6
#define GLASS             7
#define CORAL             8
#define KELP              9

#define GLASS_COUNT 5
#define SEA_LANTERN_COUNT 4 + 2
#define PRISMARINE_BRICK_COUNT 8 + (2 * 4)
#define MAGMA_COUNT 12
#define GRAVEL_COUNT 1
#define GOLD_COUNT 6
#define DARK_PRISMARINE_COUNT 4 + 4 + 4 + 4 + 4

#define BLOCK_COUNT GLASS_COUNT + SEA_LANTERN_COUNT + PRISMARINE_BRICK_COUNT + MAGMA_COUNT + GRAVEL_COUNT + GOLD_COUNT + DARK_PRISMARINE_COUNT

const Box Scene_Blocks[BLOCK_COUNT] = Box[BLOCK_COUNT](
	Box(vec3(  0    , 0   ,  0    ), vec3( 13 , 0.5 , 13  ), GLASS),
	Box(vec3(  13.5 , 6.5 ,  0    ), vec3( 0.1 , 6  , 13  ), GLASS),
	Box(vec3( -13.5 , 6.5 ,  0    ), vec3( 0.1 , 6  , 13  ), GLASS),
	Box(vec3(  0    , 6.5 ,  13.5 ), vec3( 13  , 6  , 0.1 ), GLASS),
	Box(vec3(  0    , 6.5 , -13.5 ), vec3( 13  , 6  , 0.1 ), GLASS),

	Box(vec3(  13.5 , 13 ,  13.5 ), vec3(0.5), SEA_LANTERN),
	Box(vec3(  13.5 , 13 , -13.5 ), vec3(0.5), SEA_LANTERN),
	Box(vec3( -13.5 , 13 ,  13.5 ), vec3(0.5), SEA_LANTERN),
	Box(vec3( -13.5 , 13 , -13.5 ), vec3(0.5), SEA_LANTERN),

	Box(vec3(  4.5 , 5 , 0.5 ), vec3( 0.5 , 0.5, 5.5), SEA_LANTERN),
	Box(vec3( -4.5 , 5 , 0.5 ), vec3( 0.5 , 0.5, 5.5), SEA_LANTERN),

	Box(vec3(  5.5 , 2 ,  4 ), vec3(0.5, 0.5, 1), GOLD),
	Box(vec3(  5.5 , 2 ,  1 ), vec3(0.5, 0.5, 1), GOLD),
	Box(vec3(  5.5 , 2 , -2 ), vec3(0.5, 0.5, 1), GOLD),
	Box(vec3( -5.5 , 2 ,  4 ), vec3(0.5, 0.5, 1), GOLD),
	Box(vec3( -5.5 , 2 ,  1 ), vec3(0.5, 0.5, 1), GOLD),
	Box(vec3( -5.5 , 2 , -2 ), vec3(0.5, 0.5, 1), GOLD),

	Box(vec3(  3.5 , 3 , 6.5 ), vec3(1.5, 1.5, 0.5), PRISMARINE_BRICKS),
	Box(vec3( -3.5 , 3 , 6.5 ), vec3(1.5, 1.5, 0.5), PRISMARINE_BRICKS),

	Box(vec3(  5.5 , 4 ,  5.5 ), vec3(0.5, 2.5, 0.5), PRISMARINE_BRICKS),
	Box(vec3( -5.5 , 4 ,  5.5 ), vec3(0.5, 2.5, 0.5), PRISMARINE_BRICKS),
	Box(vec3(  5.5 , 4 ,  2.5 ), vec3(0.5, 2.5, 0.5), PRISMARINE_BRICKS),
	Box(vec3( -5.5 , 4 ,  2.5 ), vec3(0.5, 2.5, 0.5), PRISMARINE_BRICKS),
	Box(vec3(  5.5 , 4 , -0.5 ), vec3(0.5, 2.5, 0.5), PRISMARINE_BRICKS),
	Box(vec3( -5.5 , 4 , -0.5 ), vec3(0.5, 2.5, 0.5), PRISMARINE_BRICKS),
	Box(vec3(  5.5 , 4 , -3.5 ), vec3(0.5, 2.5, 0.5), PRISMARINE_BRICKS),
	Box(vec3( -5.5 , 4 , -3.5 ), vec3(0.5, 2.5, 0.5), PRISMARINE_BRICKS),

	Box(vec3(  0   , 5 , 6.5 ), vec3( 5.5 , 0.5, 1.5), PRISMARINE_BRICKS),
	Box(vec3(  0   , 6 , 0.5 ), vec3( 5   , 0.5, 5.5), PRISMARINE_BRICKS),
	Box(vec3(  0   , 7 , 0.5 ), vec3( 4   , 0.5, 4.5), PRISMARINE_BRICKS),
	Box(vec3(  0   , 8 , 0.5 ), vec3( 3   , 0.5, 3.5), PRISMARINE_BRICKS),

	Box(vec3(  4.5 , 3 , 0.5 ), vec3( 0.5 , 1.5, 5.5), PRISMARINE_BRICKS),
	Box(vec3( -4.5 , 3 , 0.5 ), vec3( 0.5 , 1.5, 5.5), PRISMARINE_BRICKS),

	Box(vec3( 0 , 1 , 0 ), vec3(13, 0.5, 13), GRAVEL),

	Box(vec3(  8.5   , 1.05 ,  6.5   ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3( -6.5   , 1.05 ,  5.5   ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3(  9.5   , 1.05 , -8.5   ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3( -6.5   , 1.05 ,  8.5   ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3(  9.5   , 1.05 ,  5.5   ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3( -7.5   , 1.05 ,  6.5   ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3( -8.5   , 1.05 , -7.5   ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3( -3.5   , 1.05 , -5.5   ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3(  9.5   , 1.05 , -10.5  ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3(  10.5  , 1.05 , -9.5   ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3( -12.55 , 1.05 , -5.5   ), vec3(0.5, 0.5, 0.5), MAGMA_BLOCK),
	Box(vec3(  0.5   , 1.05 ,  12.55 ), vec3(1.0, 0.5, 0.5), MAGMA_BLOCK),
	
	Box(vec3(  13.5 , 0 ,  0    ), vec3( 0.5 , 0.5  , 13  ), DARK_PRISMARINE),
	Box(vec3( -13.5 , 0 ,  0    ), vec3( 0.5 , 0.5  , 13  ), DARK_PRISMARINE),
	Box(vec3(  0    , 0 ,  13.5 ), vec3( 13  , 0.5  , 0.5 ), DARK_PRISMARINE),
	Box(vec3(  0    , 0 , -13.5 ), vec3( 13  , 0.5  , 0.5 ), DARK_PRISMARINE),

	Box(vec3(  13.5 , 13 ,  0    ), vec3( 0.5 , 0.5  , 13  ), DARK_PRISMARINE),
	Box(vec3( -13.5 , 13 ,  0    ), vec3( 0.5 , 0.5  , 13  ), DARK_PRISMARINE),
	Box(vec3(  0    , 13 ,  13.5 ), vec3( 13  , 0.5  , 0.5 ), DARK_PRISMARINE),
	Box(vec3(  0    , 13 , -13.5 ), vec3( 13  , 0.5  , 0.5 ), DARK_PRISMARINE),
	
	Box(vec3(  13.5 , 6 ,  13.5 ), vec3( 0.5 , 6.5 , 0.5 ), DARK_PRISMARINE),
	Box(vec3( -13.5 , 6 ,  13.5 ), vec3( 0.5 , 6.5 , 0.5 ), DARK_PRISMARINE),
	Box(vec3(  13.5 , 6 , -13.5 ), vec3( 0.5 , 6.5 , 0.5 ), DARK_PRISMARINE),
	Box(vec3( -13.5 , 6 , -13.5 ), vec3( 0.5 , 6.5 , 0.5 ), DARK_PRISMARINE),
	
	Box(vec3(  14.5 , -1 ,  0    ), vec3( 0.5 , 0.5  , 15  ), DARK_PRISMARINE),
	Box(vec3( -14.5 , -1 ,  0    ), vec3( 0.5 , 0.5  , 15  ), DARK_PRISMARINE),
	Box(vec3(  0    , -1 ,  14.5 ), vec3( 14  , 0.5  , 0.5 ), DARK_PRISMARINE),
	Box(vec3(  0    , -1 , -14.5 ), vec3( 14  , 0.5  , 0.5 ), DARK_PRISMARINE),

	Box(vec3(  14.5 , 14 ,  0    ), vec3( 0.5 , 0.5  , 15  ), DARK_PRISMARINE),
	Box(vec3( -14.5 , 14 ,  0    ), vec3( 0.5 , 0.5  , 15  ), DARK_PRISMARINE),
	Box(vec3(  0    , 14 ,  14.5 ), vec3( 14  , 0.5  , 0.5 ), DARK_PRISMARINE),
	Box(vec3(  0    , 14 , -14.5 ), vec3( 14  , 0.5  , 0.5 ), DARK_PRISMARINE)
);

// INTERSECTIONS ---------------------------------------------------------------------------------------

bool f_BoxIntersection(in Ray ray, in Box box, inout float ray_length, out vec2 uv, out vec3 normal) {
	mat4 txi = mat4(1.0);
	txi[3] = vec4(box.Position, 1.0);
	mat4 txx = inverse(txi);

	vec3 rdd = (txx*vec4(ray.Ray_Direction,0.0)).xyz;
	vec3 roo = (txx*vec4(ray.Ray_Origin,1.0)).xyz;

	vec3 m = 1.0 / rdd;
	vec3 n = m*roo;
	vec3 k = abs(m) * box.Size;
	vec3 s = vec3(
		(rdd.x<0.0)?1.0:-1.0,
		(rdd.y<0.0)?1.0:-1.0,
		(rdd.z<0.0)?1.0:-1.0
	);

	vec3 t1 = -n - k;
	vec3 t2 = -n + k;

	float tNear = max( max( t1.x, t1.y ), t1.z );
	float tFar  = min( min( t2.x, t2.y ), t2.z );
	if ( tNear > tFar || tFar < 0.0)
		return false;

	vec4 res = vec4(0);
	if (tNear > 0.0)
		res = vec4( tNear, step(vec3(tNear),t1));
	else
		res = vec4(tFar, step(t2,vec3(tFar)));

	normal = (txi * vec4(-sign(rdd) * res.yzw,0.0)).xyz;
	if ( t1.x > t1.y && t1.x > t1.z ) {
		normal = normalize(txi[0].xyz * s.x);
		uv = roo.yz + rdd.yz * t1.x;
	}
	else if ( t1.y > t1.z ) {
		normal = normalize(txi[1].xyz * s.y);
		uv = roo.zx + rdd.zx * t1.y;
	}
	else {
		normal = normalize(txi[2].xyz * s.z);
		uv = roo.xy + rdd.xy * t1.z;
		
	}
	uv += 0.5;

	ray_length = tNear;
	return true;
}

// FUNCTIONS ---------------------------------------------------------------------------------------

vec3 f_HemiCube() {
	vec2 p = rand2();
	p = vec2(2. * PI * p.x, sqrt(p.y));
	return normalize(vec3(sin(p.x) * p.y, cos(p.x) * p.y, sqrt(1. - p.y * p.y)));
}

vec3 f_ConeRoughness(vec3 dir, float theta) {
	vec3 left = cross(dir, vec3(0., 1., 0.));
	left = length(left) > 0.1 ? normalize(left) : normalize(cross(dir, vec3(0., 0., 1.)));
	vec3 up = normalize(cross(dir, left));

	vec2 u = rand2();
	float cos_theta = (1. - u.x) + u.x * cos(theta);
	float sin_theta = sqrt(1. - cos_theta * cos_theta);
	float phi = u.y * 2.0 * PI;
	return normalize(
		left * cos(phi) * sin_theta +
		up   * sin(phi) * sin_theta +
		dir  * cos_theta);
}

Hit f_SceneIntersection(const in Ray ray) {
	Hit hit_data;
	hit_data.Ray_Length = MAX_DIST;
	vec3 normal = vec3(0);
	vec2 uv = vec2(0);
	bool inside = false;

	for (int i = 0; i < BLOCK_COUNT; i++) {
		float resultRayLength;
		if (f_BoxIntersection(ray, Scene_Blocks[i], resultRayLength, uv, normal)) {
			if(resultRayLength < hit_data.Ray_Length && resultRayLength > EPSILON) {
				hit_data.Ray_Length = resultRayLength;
				hit_data.Hit_Obj = i;
				hit_data.Hit_Mat = Scene_Blocks[i].Mat;
				hit_data.Hit_UV = uv;
				hit_data.Hit_Pos = ray.Ray_Origin + ray.Ray_Direction * hit_data.Ray_Length;
				hit_data.Hit_New_Dir = normal;
				hit_data.Ray_Inside = false;
			}
		}
	}
	float d = -log(rand1());
	if (d < 0.05) {
		hit_data.Ray_Length = d;
		hit_data.Hit_Obj = -1;
		hit_data.Hit_Mat = -1;
		hit_data.Hit_UV = vec2(0,0);
		hit_data.Hit_Pos = ray.Ray_Origin + ray.Ray_Direction * hit_data.Ray_Length;
		hit_data.Hit_New_Dir = refract(ray.Ray_Direction, normalize(rand3()) , 1.05) ;
		hit_data.Ray_Inside = false;
	}

	return hit_data;
}

vec3 f_EnvironmentHDR(in Ray r) {
	r.Ray_Direction = eulerToRot(vec3(0,-90,0)) * r.Ray_Direction;

	float phi = atan(r.Ray_Direction.y, r.Ray_Direction.x);
	float theta = acos(r.Ray_Direction.z);
	float u = phi / TWO_PI + 0.5;
	float v = theta / PI;

	return texture(environment_texture, vec2(u,v)).rgb * HDRI_STRENGTH;
}

vec3 f_Radiance(in Ray r){
	vec3 rad = vec3(0);
	vec3 brdf = vec3(1);

	for (int b = 0; b < RAY_BOUNCES; b++) {
		Hit hit_data = f_SceneIntersection(r);
		vec3 tangent = normalize(cross(r.Ray_Direction, hit_data.Hit_New_Dir));
		vec3 bitangent = normalize(cross(hit_data.Hit_New_Dir, tangent));
		vec3 normal = f_HemiCube();
		if (hit_data.Ray_Length >= MAX_DIST) {
			return rad + brdf * f_EnvironmentHDR(r); // MISS;
		}
		if (hit_data.Hit_Mat == GLASS) {
			float cosi = abs(dot(hit_data.Hit_New_Dir, r.Ray_Direction));
			float sini = sqrt(1. - cosi * cosi);
			float iort = 1.05;
			float iori = 1.0;
			if (hit_data.Ray_Inside){
				iori = iort;
				iort = 1.0;
			}
			float sint = snell(sini, iori, iort);
			float cost = sqrt(1.0 - sint * sint);
			float frsn = fresnel(iori, iort, cosi, cost);
			if (rand1() > frsn + 0.2){
				vec3 bitangent = normalize(r.Ray_Direction - dot(hit_data.Hit_New_Dir, r.Ray_Direction) * hit_data.Hit_New_Dir);
				r.Ray_Direction = normalize(bitangent * sint - cost * hit_data.Hit_New_Dir);
				brdf *= vec3(1.0);
			}
			else
				r.Ray_Direction = reflect(r.Ray_Direction, hit_data.Hit_New_Dir);
			r.Ray_Origin = hit_data.Hit_Pos + r.Ray_Direction * EPSILON;
			continue;
		}
		else if (hit_data.Hit_Mat == SEA_LANTERN) {
			vec2 boxuv = vec2(0,1) - hit_data.Hit_UV;
			vec2 uv = fract(boxuv)* vec2(1.0/3.0, 1.0/9.0) + vec2(0, float(9-hit_data.Hit_Mat)/9.0);
			return rad + brdf * vec3(pow(texture(block_textures, uv).r,  8), pow(texture(block_textures, uv).g,  8), pow(texture(block_textures, uv).b,  8)) * 500;
		}
		else if (hit_data.Hit_Mat == MAGMA_BLOCK) {
			vec2 boxuv = vec2(0,1) - hit_data.Hit_UV;
			vec2 uv = fract(boxuv)* vec2(1.0/3.0, 1.0/9.0) + vec2(0, float(9-hit_data.Hit_Mat)/9.0);
			return rad + brdf * vec3(pow(texture(block_textures, uv).r,  2), pow(texture(block_textures, uv).g,  2), pow(texture(block_textures, uv).b,  2)) * 2;
		}

		vec2 boxuv = vec2(0,1) - hit_data.Hit_UV;
		vec2 uv = fract(boxuv)* vec2(1.0/3.0, 1.0/9.0) + vec2(0, float(9-hit_data.Hit_Mat)/9.0);

		float roughness = texture(block_textures, uv).b;
		r.Ray_Direction = normalize(mix(reflect(r.Ray_Direction, hit_data.Hit_New_Dir), normalize(tangent * normal.x + bitangent * normal.y + hit_data.Hit_New_Dir * normal.z), roughness));
		r.Ray_Origin = hit_data.Hit_Pos + r.Ray_Direction * EPSILON;
		brdf *= texture(block_textures, uv).rgb;
	}
	return rad;
}

Ray f_CameraRay(vec2 uv) {
	vec3 projection_center = camera_pos + 0.05 * camera_z;
	vec3 projection_u = normalize(cross(camera_z, camera_y)) * 0.036;
	vec3 projection_v = normalize(cross(projection_u, camera_z)) * (0.036 / 1.0);
	return Ray(camera_pos, normalize(projection_center + (projection_u * uv.x) + (projection_v * uv.y) - camera_pos) );
}

// Main ---------------------------------------------------------------------------------------
void main() {
	if (runframe < SAMPLES) {
		rng_initialize(gl_FragCoord.xy, runframe);
		const vec2 uv = (gl_FragCoord.xy - 1.0 - resolution.xy /2.0) / max(resolution.x, resolution.y);
		const vec2 pixel_size = 1/ resolution.xy;

		vec3 col;
		for (int x = 0; x < SPP; x++) {
			for (int y = 0; y < SPP; y++) {
				vec2 subpixelUV = uv - (vec2(0.5) * pixel_size) + (vec2(float(x) / float(SPP), float(y) / float(SPP)) * pixel_size);
				col += f_Radiance(f_CameraRay(subpixelUV));
			}
		}
		col /= float(SPP * SPP);
		fragColor = vec4(col, 1);
	}
	else {
		fragColor = texture(last_frame, fragTexCoord);
	}
}