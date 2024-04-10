typedef float16 mat4x4;
typedef float3 vec3;
typedef float4 vec4;

// Hash Functions for GPU Rendering, Jarzynski et al.
// http://www.jcgt.org/published/0009/03/02/
float3 random_pcg3d(uint3 v)
{
	v = v * 1664525u + 1013904223u;
	v.x += v.y*v.z; v.y += v.z*v.x; v.z += v.x*v.y;
	v ^= v >> 16u;
	v.x += v.y*v.z; v.y += v.z*v.x; v.z += v.x*v.y;

	float3 ret;
	ret.x = ((float)v.x /0xffffffffu);
	ret.y = ((float)v.y /0xffffffffu);
	ret.z = ((float)v.z /0xffffffffu);

	return ret;
}

void MultiplyMat4Vec4(mat4x4* a, vec4* b, vec4* out)
{
    out->x = a->s0 * b->x + a->s1 * b->y + a->s2 * b->z + a->s3 * b->w;
    out->y = a->s4 * b->x + a->s5 * b->y + a->s6 * b->z + a->s7 * b->w;
    out->z = a->s8 * b->x + a->s9 * b->y + a->sa * b->z + a->sb * b->w;
    out->w = a->sc * b->x + a->sd * b->y + a->se * b->z + a->sf * b->w;
}

void MultiplyMat4Mat4(mat4x4* a, mat4x4* b, mat4x4* out)
{
    out->s0 = a->s0 * b->s0 + a->s1 * b->s4 + a->s2 * b->s8 + a->s3 * b->sc;
    out->s4 = a->s4 * b->s0 + a->s5 * b->s4 + a->s6 * b->s8 + a->s7 * b->sc;
    out->s8 = a->s8 * b->s0 + a->s9 * b->s4 + a->sa * b->s8 + a->sb * b->sc;
    out->sc = a->sc * b->s0 + a->sd * b->s4 + a->se * b->s8 + a->sf * b->sc;

    out->s1 = a->s0 * b->s1 + a->s1 * b->s5 + a->s2 * b->s9 + a->s3 * b->sd;
    out->s5 = a->s4 * b->s1 + a->s5 * b->s5 + a->s6 * b->s9 + a->s7 * b->sd;
    out->s9 = a->s8 * b->s1 + a->s9 * b->s5 + a->sa * b->s9 + a->sb * b->sd;
    out->sd = a->sc * b->s1 + a->sd * b->s5 + a->se * b->s9 + a->sf * b->sd;

    out->s2 = a->s0 * b->s2 + a->s1 * b->s6 + a->s2 * b->sa + a->s3 * b->se;
    out->s6 = a->s4 * b->s2 + a->s5 * b->s6 + a->s6 * b->sa + a->s7 * b->se;
    out->sa = a->s8 * b->s2 + a->s9 * b->s6 + a->sa * b->sa + a->sb * b->se;
    out->se = a->sc * b->s2 + a->sd * b->s6 + a->se * b->sa + a->sf * b->se;

    out->s3 = a->s0 * b->s3 + a->s1 * b->s7 + a->s2 * b->sb + a->s3 * b->sf;
    out->s7 = a->s4 * b->s3 + a->s5 * b->s7 + a->s6 * b->sb + a->s7 * b->sf;
    out->sb = a->s8 * b->s3 + a->s9 * b->s7 + a->sa * b->sb + a->sb * b->sf;
    out->sf = a->sc * b->s3 + a->sd * b->s7 + a->se * b->sb + a->sf * b->sf;
}

bool InverseMat4x4(mat4x4* m, mat4x4* invOut)
{
    mat4x4 inv;
    float det;
    int i;

    inv.s0 = m->s5 * m->sa * m->sf - 
             m->s5 * m->sb * m->se - 
             m->s9 * m->s6 * m->sf + 
             m->s9 * m->s7 * m->se +
             m->sd * m->s6 * m->sb - 
             m->sd * m->s7 * m->sa;

    inv.s4 = -m->s4 * m->sa * m->sf + 
              m->s4 * m->sb * m->se + 
              m->s8 * m->s6 * m->sf - 
              m->s8 * m->s7 * m->se - 
              m->sc * m->s6 * m->sb + 
              m->sc * m->s7 * m->sa;

    inv.s8 = m->s4 * m->s9 * m->sf - 
             m->s4 * m->sb * m->sd - 
             m->s8 * m->s5 * m->sf + 
             m->s8 * m->s7 * m->sd + 
             m->sc * m->s5 * m->sb - 
             m->sc * m->s7 * m->s9;

    inv.sc =  -m->s4 * m->s9 * m->se + 
               m->s4 * m->sa * m->sd +
               m->s8 * m->s5 * m->se - 
               m->s8 * m->s6 * m->sd - 
               m->sc * m->s5 * m->sa + 
               m->sc * m->s6 * m->s9;

    inv.s1 = -m->s1 * m->sa * m->sf + 
              m->s1 * m->sb * m->se + 
              m->s9 * m->s2 * m->sf - 
              m->s9 * m->s3 * m->se - 
              m->sd * m->s2 * m->sb + 
              m->sd * m->s3 * m->sa;

    inv.s5 = m->s0 * m->sa * m->sf - 
             m->s0 * m->sb * m->se - 
             m->s8 * m->s2 * m->sf + 
             m->s8 * m->s3 * m->se + 
             m->sc * m->s2 * m->sb - 
             m->sc * m->s3 * m->sa;

    inv.s9 = -m->s0 * m->s9 * m->sf + 
              m->s0 * m->sb * m->sd + 
              m->s8 * m->s1 * m->sf - 
              m->s8 * m->s3 * m->sd - 
              m->sc * m->s1 * m->sb + 
              m->sc * m->s3 * m->s9;

    inv.sd  = m->s0 * m->s9 * m->se - 
              m->s0 * m->sa * m->sd - 
              m->s8 * m->s1 * m->se + 
              m->s8 * m->s2 * m->sd + 
              m->sc * m->s1 * m->sa - 
              m->sc * m->s2 * m->s9;

    inv.s2 = m->s1 * m->s6 * m->sf - 
             m->s1 * m->s7 * m->se - 
             m->s5 * m->s2 * m->sf + 
             m->s5 * m->s3 * m->se + 
             m->sd * m->s2 * m->s7 - 
             m->sd * m->s3 * m->s6;

    inv.s6 = -m->s0 * m->s6 * m->sf + 
              m->s0 * m->s7 * m->se + 
              m->s4 * m->s2 * m->sf - 
              m->s4 * m->s3 * m->se - 
              m->sc * m->s2 * m->s7 + 
              m->sc * m->s3 * m->s6;

    inv.sa =  m->s0 * m->s5 * m->sf - 
              m->s0 * m->s7 * m->sd - 
              m->s4 * m->s1 * m->sf + 
              m->s4 * m->s3 * m->sd + 
              m->sc * m->s1 * m->s7 - 
              m->sc * m->s3 * m->s5;

    inv.se =  -m->s0 * m->s5 * m->se + 
               m->s0 * m->s6 * m->sd + 
               m->s4 * m->s1 * m->se - 
               m->s4 * m->s2 * m->sd - 
               m->sc * m->s1 * m->s6 + 
               m->sc * m->s2 * m->s5;

    inv.s3 = -m->s1 * m->s6 * m->sb + 
              m->s1 * m->s7 * m->sa + 
              m->s5 * m->s2 * m->sb - 
              m->s5 * m->s3 * m->sa - 
              m->s9 * m->s2 * m->s7 + 
              m->s9 * m->s3 * m->s6;

    inv.s7 = m->s0 * m->s6 * m->sb - 
             m->s0 * m->s7 * m->sa - 
             m->s4 * m->s2 * m->sb + 
             m->s4 * m->s3 * m->sa + 
             m->s8 * m->s2 * m->s7 - 
             m->s8 * m->s3 * m->s6;

    inv.sb  = -m->s0 * m->s5 * m->sb + 
               m->s0 * m->s7 * m->s9 + 
               m->s4 * m->s1 * m->sb - 
               m->s4 * m->s3 * m->s9 - 
               m->s8 * m->s1 * m->s7 + 
               m->s8 * m->s3 * m->s5;

    inv.sf  = m->s0 * m->s5 * m->sa - 
              m->s0 * m->s6 * m->s9 - 
              m->s4 * m->s1 * m->sa + 
              m->s4 * m->s2 * m->s9 + 
              m->s8 * m->s1 * m->s6 - 
              m->s8 * m->s2 * m->s5;

    det = m->s0 * inv.s0 + m->s1 * inv.s4 + m->s2 * inv.s8 + m->s3 * inv.sc;

    if (det == 0)
        return false;

    det = 1.0 / det;
    *invOut = inv * det;

    return true;
}

void EulerXToMat4x4(float thetaX, mat4x4* out)
{
    out->s0 = 1;
    out->s1 = 0;
    out->s2 = 0;
    out->s3 = 0;

    out->s4 = 0;
    out->s5 =  cos(thetaX);
    out->s6 = -sin(thetaX);
    out->s7 = 0;

    out->s8 = 0;
    out->s9 = sin(thetaX);
    out->sa = cos(thetaX);
    out->sb = 0;

    out->sc = 0;
    out->sd = 0;
    out->se = 0;
    out->sf = 1;
}

void EulerYToMat4x4(float thetaY, mat4x4* out)
{
    out->s0 = cos(thetaY);
    out->s1 = 0;
    out->s2 = sin(thetaY);
    out->s3 = 0;

    out->s4 = 0;
    out->s5 = 1;
    out->s6 = 0;
    out->s7 = 0;

    out->s8 = -sin(thetaY);
    out->s9 = 0;
    out->sa = cos(thetaY);
    out->sb = 0;

    out->sc = 0;
    out->sd = 0;
    out->se = 0;
    out->sf = 1;
}

void EulerZToMat4x4(float thetaZ, mat4x4* out)
{
    out->s0 =  cos(thetaZ);
    out->s1 = -sin(thetaZ);
    out->s2 = 0;
    out->s3 = 0;

    out->s4 = sin(thetaZ);
    out->s5 = cos(thetaZ);
    out->s6 = 0;
    out->s7 = 0;

    out->s8 = 0;
    out->s9 = 0;
    out->sa = 1;
    out->sb = 0;

    out->sc = 0;
    out->sd = 0;
    out->se = 0;
    out->sf = 1;
}

void TransformToTranslate(mat4x4* a, vec3* out)
{
    out->x = a->s3;
    out->y = a->s7;
    out->z = a->sb;
}

void Vec4ToMat4x4(vec4* r0, vec4* r1, vec4* r2, vec4* r3, mat4x4* out)
{
    out->s0123 = *r0;
    out->s4567 = *r1;
    out->s89ab = *r2;
    out->scdef = *r3;
}