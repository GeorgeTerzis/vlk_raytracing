// glslc -fshader-stage=comp  compute.comp.glsl -o noise.spv
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;


layout(set = 0, binding = 0) buffer OutputBuffer {
    float data[];
} output_buffer;

layout(set = 0, binding = 1) buffer InputBuffer {
    float data[];
} input_buffer;

layout(push_constant) uniform PC {
    uint width;
    uint height;
} pc;

float rand1d(vec3 p) {
    return fract(sin(p.x*1020.+p.y*251.+p.z*21.0)*562447.);
}

float rand1d(vec2 p) {
    return fract(sin(p.x*1020.+p.y*251.)*562447.);
}

float rand2d(vec2 p) {
    return (fract(sin(p.x*1020.+p.y*251.)*562447.));
}

//with derivitive
vec4 noised(vec3 x) {
    vec3 p = floor(x);
    vec3 w = smoothstep(0.0,1.0,fract(x));

    vec3 u = w*w*w*(w*(w*6.0-15.0)+10.0);
    vec3 du = 30.0*w*w*(w*(w-2.0)+1.0);

    float a = rand1d( p+vec3(0,0,0) );
    float b = rand1d( p+vec3(1,0,0) );
    float c = rand1d( p+vec3(0,1,0) );
    float d = rand1d( p+vec3(1,1,0) );
    float e = rand1d( p+vec3(0,0,1) );
    float f = rand1d( p+vec3(1,0,1) );
    float g = rand1d( p+vec3(0,1,1) );
    float h = rand1d( p+vec3(1,1,1) );

    float k0 =   a;
    float k1 =   b - a;
    float k2 =   c - a;
    float k3 =   e - a;
    float k4 =   a - b - c + d;
    float k5 =   a - c - e + g;
    float k6 =   a - b - e + f;
    float k7 = - a + b + c - d + e - f - g + h;

    return vec4( (k0 + k1*u.x + k2*u.y + k3*u.z + k4*u.x*u.y + k5*u.y*u.z + k6*u.z*u.x + k7*u.x*u.y*u.z),
                 2.0* du * vec3( k1 + k4*u.y + k6*u.z + k7*u.y*u.z,
                                 k2 + k5*u.z + k4*u.x + k7*u.z*u.x,
                                 k3 + k6*u.x + k5*u.y + k7*u.x*u.y ) );
}

const mat2 m = mat2(0.8,-0.6,0.6,0.8);
float fbm(vec2 p){
  float a = 0.0;
  float b = 1.0;
  vec2  d = vec2(0.0);
  for( int i=0; i < 10; i++ ){
    vec3 n= noised(vec3(m*p,1)).xyz;
    d +=n.yz;
    a +=b*n.x/(1.0+dot(d,d));
    b *=0.5;
    p=m*p*2.;
  }
  return a;
}

vec2 grad(vec2 pos){
  float twoPi = 6.2885;
  float angle = rand1d(pos)*twoPi;
  return vec2(cos(angle), sin(angle));
}
vec3 grad(vec3 pos){
  float twoPi = 6.2885;
  float angle = rand1d(pos)*twoPi;
  return normalize(vec3(cos(angle), sin(angle), cos(angle)));
}

float pnoise(vec2 uv){
  const vec2 center = uv + vec2(0.5);
  const vec2 id = floor(uv);
  const vec2 fract = smoothstep(0.0,1.0,fract(uv));

  const vec2 bl = id;
  const vec2 br = id+vec2(1,0);
  const vec2 tl = id+vec2(0,1);
  const vec2 tr = id+vec2(1,1);

  const float dbl = dot(center - bl,grad(bl));
  const float dbr = dot(center - br,grad(br));
  const float dtl = dot(center - tl,grad(tl));
  const float dtr = dot(center - tr,grad(tr));

  const float b = mix(dbl,dbr,fract.x);
  const float t = mix(dtl,dtr,fract.x);

  const float tb = mix(b,t,fract.y);
  return tb;
}

float pnoise(vec3 uv){
  const vec3 center = uv + vec3(0.5);
  const vec3 id = floor(uv);
  const vec3 fract = smoothstep(0.0,1.0,fract(uv));

  const vec3  bl = id+vec3(0,0,0);
  const vec3  br = id+vec3(1,0,0);
  const vec3  tl = id+vec3(0,1,0);
  const vec3  tr = id+vec3(1,1,0);
  const float dbl = dot(center - bl,grad(bl));
  const float dbr = dot(center - br,grad(br));
  const float dtl = dot(center - tl,grad(tl));
  const float dtr = dot(center - tr,grad(tr));
  const float b = mix(dbl,dbr,fract.x);
  const float t = mix(dtl,dtr,fract.x);
  const float tb = mix(b,t,fract.y);

  const vec3  zbl = id+vec3(0,0,1);
  const vec3  zbr = id+vec3(1,0,1);
  const vec3  ztl = id+vec3(0,1,1);
  const vec3  ztr = id+vec3(1,1,1);
  const float zdbl = dot(center - zbl,grad(zbl));
  const float zdbr = dot(center - zbr,grad(zbr));
  const float zdtl = dot(center - ztl,grad(ztl));
  const float zdtr = dot(center - ztr,grad(ztr));
  const float zb = mix(zdbl,zdbr,fract.x);
  const float zt = mix(zdtl,zdtr,fract.x);
  const float ztb = mix(b,t,fract.y);

  const float q = mix(tb,ztb,fract.z);

  return q;
}

mat3 rotY(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(
        c, 0.0, -s,
        0.0, 1.0, 0.0,
        s, 0.0, c
    );
}


float abspfbm(vec2 uv){
  float str = 1;
  float str_decay = 0.5;
  float scale = 1.5f;
  float val = 0.0f;
  for(int i = 0; i < 15; i++){
    float v = abs(pnoise(uv));
    v = 1 - v;
    v = v*v*v;
    val += str*v;
    uv *= mat2(rotY(4*3.14))*vec2(scale);
    str *= str_decay;
  }

  return val;
}
float pfbm(vec2 uv){
  float str = 1;
  float str_decay = 0.5;
  float scale = 2.0f;
  float val = 0.0f;
  for(int i = 0; i < 12; i++){
    float v = (pnoise(uv));
    val += str*v;
    uv *= mat2(rotY(4*3.14))*vec2(scale);
    str *= str_decay;
  }

  return val;
}
//float pfbm(vec3 uv){
//  float str = 1;
//  float str_decay = 0.5;
//  float scale = 2.0f;
//  float val = 0.0f;
//  for(int i = 0; i < 4; i++){
////    val += str*abs(pnoise(uv + val*0.6));
//    val += str*(pnoise(uv));
//    uv = rotZ(0.5)*uv;
//    uv *= vec3(scale);
//    str *= str_decay;
//  }
//
//  return val;
//}


float sharp(vec2 uv, float power) {
  return fbm(uv) * pow(fbm(uv), power);
}

float output_function(vec2 uv) {
  uv *= 1.2;
  //float f = fbm(uv);
  float h2 = abspfbm(uv* 10);
  float h = 0;
  h += (sharp(uv*2, 1.2)*0.3);

  // h += 1 -pow(abs(pfbm((uv*30 + 600 + 50)*0.3)*0.2), 1.2);
  h += pfbm(uv*2);
  // h += fbm((uv*40)*0.3)*0.03;
  // h += pfbm((uv*1)*0.3)*0.1;
  h += pfbm(uv*6 + 10)*0.1;
  // h += pfbm(uv*2 - 10)*0.2;
  // h = 1 - abs(h);
  // h *= 0.6;
  // h *=  clamp(1,0,smoothstep(1,0,dot(uv,uv) - 1));
  return h;
}
void main() {
    const uint x = gl_GlobalInvocationID.x;
    const uint y = gl_GlobalInvocationID.y;

    if (x >= pc.width || y >= pc.height) return;

    float fx = float(x) / float(pc.width);
    float fy = float(y) / float(pc.height);

    vec2 coord = vec2(fx, fy);
    
    uint index = y * pc.width + x;

    output_buffer.data[index] = output_function(coord);
}
