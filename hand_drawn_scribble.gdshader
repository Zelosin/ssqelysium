// hand_drawn_scribble GDShader v25 (2D canvas_item, editor/web parity)
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform sampler2D source_texture : filter_linear, repeat_disable;

uniform float boil_interval : hint_range(0.05, 2.0, 0.01) = 0.25;
uniform float cell_size : hint_range(8.0, 128.0, 1.0) = 28.0;
uniform float edge_threshold : hint_range(0.01, 0.95, 0.01) = 0.1;
uniform float line_draw_chance : hint_range(0.0, 100.0, 1.0) = 45.0;
uniform float line_length : hint_range(0.5, 16.0, 0.25) = 3.0;
uniform float line_width : hint_range(0.5, 24.0, 0.5) = 2.5;
uniform float chaos_offset_px : hint_range(0.0, 200.0, 1.0) = 48.0;
uniform float boil_angle_spread : hint_range(0.0, 180.0, 5.0) = 180.0;
uniform float chaos_angle : hint_range(0.0, 45.0, 1.0) = 20.0;
uniform float contour_hold : hint_range(0.0, 1.0, 0.05) = 0.0;
uniform float line_wiggle : hint_range(0.0, 24.0, 0.5) = 3.0;
uniform float line_width_variation : hint_range(0.0, 1.0, 0.05) = 0.75;
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float hatch_draw_chance : hint_range(0.0, 100.0, 1.0) = 20.0;
uniform vec4 hatch_color : source_color = vec4(0.82, 0.82, 0.82, 1.0);
uniform float hatch_opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float hatch_frame_margin : hint_range(0.0, 64.0, 1.0) = 12.0;
uniform float hatch_length_px : hint_range(1.0, 400.0, 1.0) = 24.0;
uniform float hatch_max_length_px : hint_range(16.0, 2000.0, 1.0) = 128.0;
uniform float hatch_angle_spread : hint_range(0.0, 90.0, 5.0) = 25.0;
uniform float hatch_width : hint_range(0.5, 8.0, 0.5) = 1.4;
uniform float hatch_wall_jitter : hint_range(0.0, 0.45, 0.05) = 0.15;
uniform float hatch_offset_px : hint_range(0.0, 40.0, 0.5) = 4.0;
uniform float hatch_wiggle : hint_range(0.0, 24.0, 0.5) = 2.5;
uniform float hatch_width_variation : hint_range(0.0, 1.0, 0.05) = 0.75;
uniform float hatch_allow_adjacent : hint_range(0.0, 1.0, 1.0) = 0.0;
uniform float hatch_density_radius : hint_range(4.0, 48.0, 1.0) = 14.0;
uniform float hatch_edge_hits_min : hint_range(0.0, 13.0, 1.0) = 0.0;
uniform float hatch_edge_hits_max : hint_range(1.0, 13.0, 1.0) = 6.0;
uniform float hatch_path_hits_max : hint_range(0.0, 5.0, 1.0) = 1.0;
uniform vec4 background_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool preserve_alpha = false;
uniform float fade_alpha : hint_range(0.0, 1.0, 0.01) = 1.0;
// Set from @tool script so boil animates in the editor (TIME is static there).
uniform float effect_time = 0.0;

float hash21(vec2 p)
{
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

float luminance(vec3 c)
{
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec2 get_uv_size() {
	return vec2(textureSize(source_texture, 0));
}

vec2 uv_pixel_interval_val() {
	return vec2(1.0) / get_uv_size();
}

vec2 clampUv(vec2 uv)
{
    vec2 px = uv_pixel_interval_val();
    return clamp(uv, px * 2.0, 1.0 - px * 2.0);
}

vec4 sample_source(vec2 uv) {
	return texture(source_texture, clampUv(uv));
}

vec3 sample_source_rgb(vec2 uv) {
	return sample_source(uv).rgb;
}

float shader_time() {
	// effect_time from scribble_sprite.gd; TIME fallback + keeps editor time dependency.
	float t = effect_time > 0.001 ? effect_time : TIME;
	return t + TIME * 0.0000001;
}

float edgeAt(vec2 uv)
{
    vec4 c = sample_source(uv);
    if (c.a < 0.001) {
        return 0.0;
    }
    float lum = luminance(c.rgb);
    if (lum < 0.05) {
        return c.a;
    }
    return lum;
}

float edgeAtPix(vec2 pix)
{
    return edgeAt(pix / get_uv_size());
}

bool hatchNearImageFrame(vec2 pix)
{
    float m = hatch_frame_margin;
    if (m <= 0.5) {
        return false;
    }
    return pix.x < m || pix.y < m || pix.x > (get_uv_size().x - m) || pix.y > (get_uv_size().y - m);
}

vec2 rotate2(vec2 v, float rad)
{
    float c = cos(rad);
    float s = sin(rad);
    return vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

float wobblySegment(vec2 p, vec2 a, vec2 b, float width, float wig, float ph)
{
    vec2 ab = b - a;
    float abLen = length(ab);
    if (abLen < 1e-4) {
        return 0.0;
    }
    vec2 dir = ab / abLen;
    vec2 perp = vec2(-dir.y, dir.x);
    float t = clamp(dot(p - a, dir) / abLen, 0.0, 1.0);
    vec2 proj = a + dir * (t * abLen);
    float wob = sin(t * 14.0 + ph) * wig;
    float d = length(p - proj - perp * wob);
    return 1.0 - smoothstep(width * 0.35, width * 1.05, d);
}

float capsuleSegmentInk(vec2 p, vec2 a, vec2 b, float wA, float wB)
{
    vec2 ab = b - a;
    float abLen2 = dot(ab, ab);
    if (abLen2 < 1e-6) {
        float w = (wA + wB) * 0.5;
        float d = length(p - a);
        return 1.0 - smoothstep(w * 0.32, w * 1.08, d);
    }
    float h = clamp(dot(p - a, ab) / abLen2, 0.0, 1.0);
    vec2 q = a + ab * h;
    float w = mix(wA, wB, h);
    float d = length(p - q);
    return 1.0 - smoothstep(w * 0.32, w * 1.08, d);
}

float handLineOffset(float t, float style, float ph, float amp)
{
    if (style < 0.5) {
        return sin(t * 3.14159265 + ph) * amp * 0.55;
    }
    if (style >= 0.5 && style < 1.5) {
        float f = fract(t * 6.0 + ph * 0.13);
        return (f * 2.0 - 1.0) * amp * 0.95;
    }
    if (style >= 1.5 && style < 2.5) {
        return sin(t * 2.3 + ph * 0.7) * amp * 0.45
            + sin(t * 11.0 + ph * 1.9) * amp * 0.3
            + (hash21(vec2(t * 7.0 + ph, ph)) * 2.0 - 1.0) * amp * 0.35;
    }
    if (style >= 2.5 && style < 3.5) {
        return (hash21(vec2(t * 17.0 + ph, ph + 2.4)) * 2.0 - 1.0) * amp;
    }
    if (style >= 3.5 && style < 4.5) {
        float tri = abs(fract(t * 4.5 + ph * 0.2) * 2.0 - 1.0);
        return (tri * 2.0 - 1.0) * amp * 0.75 + sin(t * 19.0 + ph) * amp * 0.2;
    }
    float bulge = sin(t * 3.14159265);
    return bulge * amp * 0.42
        + (hash21(vec2(t * 9.0, ph + 5.1)) * 2.0 - 1.0) * amp * 0.38;
}

float handLineWidthAt(float t, float baseW, float style, float ph, float varAmt)
{
    float w = baseW;
    float pulse = 0.58 + 0.42 * sin(t * 6.2831853 + ph * 2.3);
    float grain = 0.68 + 0.32 * hash21(vec2(t * 13.0 + ph, ph + 0.9));
    w *= mix(1.0, pulse * grain, varAmt);
    if (style >= 4.5) {
        float taper = sin(t * 3.14159265);
        w *= mix(1.0, 0.2 + taper * 1.25, varAmt);
    }
    if (style >= 0.5 && style < 1.5) {
        w *= mix(1.0, 0.75 + 0.25 * fract(t * 8.0 + ph), varAmt);
    }
    return max(w, 0.35);
}

float handDrawnSegment(vec2 p, vec2 a, vec2 b, float baseW, vec2 cellId, float seed, float roughAmp, float widthVar)
{
    vec2 ab = b - a;
    float seg_len = length(ab);
    if (seg_len < 1e-4) {
        return 0.0;
    }
    vec2 dir = ab / seg_len;
    vec2 perp_vec = vec2(-dir.y, dir.x);
    float ph = seed * 2.17 + hash21(cellId) * 6.28;
    float style = min(floor(hash21(cellId + vec2(seed, 40.0)) * 6.0), 5.0);
    float amp = roughAmp * (0.65 + 0.7 * hash21(cellId + vec2(seed, 41.0)));

    float ink = 0.0;
    const float SEGS = 9.0;
    for (uint i = 0u; i < 9u; i++) {
        float fi = float(i);
        float fi1 = float(i + 1u);
        float t0 = fi / SEGS;
        float t1 = fi1 / SEGS;
        vec2 c0 = a + dir * (t0 * seg_len) + perp_vec * handLineOffset(t0, style, ph, amp);
        vec2 c1 = a + dir * (t1 * seg_len) + perp_vec * handLineOffset(t1, style, ph, amp);
        float w0 = handLineWidthAt(t0, baseW, style, ph, widthVar);
        float w1 = handLineWidthAt(t1, baseW, style, ph, widthVar);
        ink = max(ink, capsuleSegmentInk(p, c0, c1, w0, w1));
    }
    return ink;
}

void analyzeCellSides(vec2 cellId, float cs, out vec4 sideStrength, out vec4 sidePos)
{
    vec2 o = cellId * cs / get_uv_size();
    vec2 s = vec2(cs / get_uv_size().x, cs / get_uv_size().y);

    vec2 uvT0 = vec2(o.x + s.x * 0.2, o.y);
    vec2 uvT1 = vec2(o.x + s.x * 0.5, o.y);
    vec2 uvT2 = vec2(o.x + s.x * 0.8, o.y);
    float eT0 = edgeAt(uvT0);
    float eT1 = edgeAt(uvT1);
    float eT2 = edgeAt(uvT2);
    sideStrength.x = max(eT0, max(eT1, eT2));
    sidePos.x = eT0 > eT1 ? (eT0 > eT2 ? 0.2 : 0.8) : (eT1 > eT2 ? 0.5 : 0.8);

    vec2 uvR0 = vec2(o.x + s.x, o.y + s.y * 0.2);
    vec2 uvR1 = vec2(o.x + s.x, o.y + s.y * 0.5);
    vec2 uvR2 = vec2(o.x + s.x, o.y + s.y * 0.8);
    float eR0 = edgeAt(uvR0);
    float eR1 = edgeAt(uvR1);
    float eR2 = edgeAt(uvR2);
    sideStrength.y = max(eR0, max(eR1, eR2));
    sidePos.y = eR0 > eR1 ? (eR0 > eR2 ? 0.2 : 0.8) : (eR1 > eR2 ? 0.5 : 0.8);

    vec2 uvB0 = vec2(o.x + s.x * 0.2, o.y + s.y);
    vec2 uvB1 = vec2(o.x + s.x * 0.5, o.y + s.y);
    vec2 uvB2 = vec2(o.x + s.x * 0.8, o.y + s.y);
    float eB0 = edgeAt(uvB0);
    float eB1 = edgeAt(uvB1);
    float eB2 = edgeAt(uvB2);
    sideStrength.z = max(eB0, max(eB1, eB2));
    sidePos.z = eB0 > eB1 ? (eB0 > eB2 ? 0.2 : 0.8) : (eB1 > eB2 ? 0.5 : 0.8);

    vec2 uvL0 = vec2(o.x, o.y + s.y * 0.2);
    vec2 uvL1 = vec2(o.x, o.y + s.y * 0.5);
    vec2 uvL2 = vec2(o.x, o.y + s.y * 0.8);
    float eL0 = edgeAt(uvL0);
    float eL1 = edgeAt(uvL1);
    float eL2 = edgeAt(uvL2);
    sideStrength.w = max(eL0, max(eL1, eL2));
    sidePos.w = eL0 > eL1 ? (eL0 > eL2 ? 0.2 : 0.8) : (eL1 > eL2 ? 0.5 : 0.8);
}

float sideStrengthAt(float side, vec4 str)
{
    if (side < 0.5) {
        return str.x;
    }
    if (side < 1.5) {
        return str.y;
    }
    if (side < 2.5) {
        return str.z;
    }
    return str.w;
}

float sidePosAlong(float side, vec4 pos)
{
    if (side < 0.5) {
        return pos.x;
    }
    if (side < 1.5) {
        return pos.y;
    }
    if (side < 2.5) {
        return pos.z;
    }
    return pos.w;
}

vec2 sidePoint(float side, float tAlong, float cs)
{
    if (side < 0.5) {
        return vec2(tAlong * cs, 0.0);
    }
    if (side < 1.5) {
        return vec2(cs, tAlong * cs);
    }
    if (side < 2.5) {
        return vec2(tAlong * cs, cs);
    }
    return vec2(0.0, tAlong * cs);
}

bool cellPassesDrawChance(vec2 cellId, float seed, float chancePct)
{
    if (chancePct <= 0.0) {
        return false;
    }
    if (chancePct >= 100.0) {
        return true;
    }
    return hash21(cellId + vec2(seed, 31.7)) < (chancePct * 0.01);
}

bool pickCellEdgePair(vec2 cellId, float cs, out float sideA, out float sideB, out vec4 pos)
{
    vec4 str;
    analyzeCellSides(cellId, cs, str, pos);

    float thresh = clamp(edge_threshold, 0.01, 0.95);
    float hit0 = step(thresh, str.x);
    float hit1 = step(thresh, str.y);
    float hit2 = step(thresh, str.z);
    float hit3 = step(thresh, str.w);
    float hitCount = hit0 + hit1 + hit2 + hit3;

    if (hitCount < 2.0) {
        return false;
    }

    sideA = 0.0;
    sideB = 1.0;
    float bestA = str.x * hit0;
    float bestB = str.y * hit1;

    if (str.y * hit1 > bestA) { bestA = str.y * hit1; sideA = 1.0; }
    if (str.z * hit2 > bestA) { bestA = str.z * hit2; sideA = 2.0; }
    if (str.w * hit3 > bestA) { bestA = str.w * hit3; sideA = 3.0; }

    bestB = 0.0;
    if (sideA > 0.5 && str.x * hit0 > bestB) { bestB = str.x * hit0; sideB = 0.0; }
    if (abs(sideA - 1.0) > 0.5 && str.y * hit1 > bestB) { bestB = str.y * hit1; sideB = 1.0; }
    if (abs(sideA - 2.0) > 0.5 && str.z * hit2 > bestB) { bestB = str.z * hit2; sideB = 2.0; }
    if (abs(sideA - 3.0) > 0.5 && str.w * hit3 > bestB) { bestB = str.w * hit3; sideB = 3.0; }

    return abs(sideA - sideB) > 0.5 && bestB >= thresh;
}

bool pickOppositeStrokeWalls(vec2 cellId, float cs, float seed, float thresh,
    vec4 str, vec4 pos, out float sideA, out float sideB)
{
    float pairPick = min(floor(hash21(cellId + vec2(seed, 201.0)) * 2.0), 1.0);

    for (int k = 0; k < 2; k++) {
        float fk = float(k);
        float pi = mod(pairPick + fk, 2.0);
        float sa = (pi < 0.5) ? 0.0 : 1.0;
        float sb = (pi < 0.5) ? 2.0 : 3.0;
        if (sideStrengthAt(sa, str) >= thresh && sideStrengthAt(sb, str) >= thresh) {
            sideA = sa;
            sideB = sb;
            return true;
        }
    }
    return false;
}

bool pickCellStrokeChord(vec2 cellId, float cs, float seed, out vec2 pA, out vec2 pB)
{
    vec4 str;
    vec4 pos;
    analyzeCellSides(cellId, cs, str, pos);

    float thresh = clamp(edge_threshold, 0.01, 0.95);
    vec2 origin = cellId * cs;
    float wallJit = hatch_wall_jitter;

    float sideA;
    float sideB;
    if (pickOppositeStrokeWalls(cellId, cs, seed, thresh, str, pos, sideA, sideB)) {
        float ta = sidePosAlong(sideA, pos);
        float tb = sidePosAlong(sideB, pos);
        ta += (hash21(cellId + vec2(seed, 211.0)) * 2.0 - 1.0) * wallJit;
        tb += (hash21(cellId + vec2(seed, 212.0)) * 2.0 - 1.0) * wallJit;
        ta = clamp(ta, 0.0, 1.0);
        tb = clamp(tb, 0.0, 1.0);
        pA = origin + sidePoint(sideA, ta, cs);
        pB = origin + sidePoint(sideB, tb, cs);
        return true;
    }

    if (hatch_allow_adjacent < 0.5) {
        return false;
    }

    if (!pickCellEdgePair(cellId, cs, sideA, sideB, pos)) {
        return false;
    }

    float ta = sidePosAlong(sideA, pos);
    float tb = sidePosAlong(sideB, pos);
    ta += (hash21(cellId + vec2(seed, 221.0)) * 2.0 - 1.0) * wallJit;
    tb += (hash21(cellId + vec2(seed, 222.0)) * 2.0 - 1.0) * wallJit;
    ta = clamp(ta, 0.0, 1.0);
    tb = clamp(tb, 0.0, 1.0);
    pA = origin + sidePoint(sideA, ta, cs);
    pB = origin + sidePoint(sideB, tb, cs);
    return true;
}

float countEdgeHitsFast(vec2 centerPix, float radiusPx, float thresh)
{
    float r = max(radiusPx, 2.0);
    float hits = 0.0;
    hits += step(thresh, edgeAtPix(centerPix));
    hits += step(thresh, edgeAtPix(centerPix + vec2(r, 0.0)));
    hits += step(thresh, edgeAtPix(centerPix + vec2(-r, 0.0)));
    hits += step(thresh, edgeAtPix(centerPix + vec2(0.0, r)));
    hits += step(thresh, edgeAtPix(centerPix + vec2(0.0, -r)));
    return hits;
}

bool hatchOriginDensityOk(vec2 originPix, float cs, float thresh)
{
    float hitsNear = countEdgeHitsFast(originPix, hatch_density_radius, thresh);
    float minHits = min(hatch_edge_hits_min, hatch_edge_hits_max);
    float maxHits = max(hatch_edge_hits_min, hatch_edge_hits_max);
    if (hitsNear > maxHits) {
        return false;
    }
    if (hitsNear >= minHits) {
        return true;
    }
    float wideR = max(cs * 1.25, hatch_density_radius + 4.0);
    return countEdgeHitsFast(originPix, wideR, thresh) >= 1.0;
}

bool rayCrossGap(vec2 origin, vec2 dir, float dMax, float minGapLen, float thresh,
    out vec2 outA, out vec2 outB, out float gapLen)
{
    float stepPx = max(8.0, dMax / 20.0);
    float offThresh = thresh * 0.72;
    float hitThresh = thresh;

    float d = 0.0;
    int phase = 0;
    float gapStart = 0.0;
    float Strength = min(ceil(dMax / stepPx), 20.0);

    gapLen = 0.0;
    outA = origin;
    outB = origin;

    for (int i = 0; i <= 20; i++) {
        float fi_ray = float(i);
        if (fi_ray > Strength) {
            break;
        }
        d += stepPx;
        if (d > dMax) {
            break;
        }
        float e = edgeAtPix(origin + dir * d);
        if (phase == 0) {
            if (e < offThresh) {
                phase = 1;
                gapStart = d;
            }
        } else if (phase == 1) {
            if (e >= hitThresh) {
                vec2 hitPix = origin + dir * d;
                if (!hatchNearImageFrame(hitPix)) {
                    gapLen = d - gapStart;
                    if (gapLen < minGapLen) {
                        return false;
                    }
                    outA = origin + dir * gapStart;
                    outB = hitPix;
                    return true;
                }
            }
        }
    }
    return false;
}

bool hatchTryBestRay(vec2 origin, vec2 crossDir, float dMax, float minLen, float thresh,
    out vec2 pA, out vec2 pB)
{
    vec2 out0;
    vec2 out1;
    float gapLen;
    bool ok = rayCrossGap(origin, crossDir, dMax, minLen, thresh, out0, out1, gapLen);
    if (ok) {
        pA = out0;
        pB = out1;
        return true;
    }
    ok = rayCrossGap(origin, -crossDir, dMax, minLen, thresh, out0, out1, gapLen);
    if (ok) {
        pA = out0;
        pB = out1;
        return true;
    }
    return false;
}

float cellLineInk(vec2 globalPix, vec2 cellId, float cs, float seed)
{
    if (!cellPassesDrawChance(cellId, seed, line_draw_chance)) {
        return 0.0;
    }

    float sideA;
    float sideB;
    vec4 pos;
    if (!pickCellEdgePair(cellId, cs, sideA, sideB, pos)) {
        return 0.0;
    }

    vec2 origin = cellId * cs;
    vec2 pA = origin + sidePoint(sideA, sidePosAlong(sideA, pos), cs);
    vec2 pB = origin + sidePoint(sideB, sidePosAlong(sideB, pos), cs);

    vec2 jA = vec2(
        hash21(cellId * 3.11 + vec2(seed, 9.0)) * 2.0 - 1.0,
        hash21(cellId * 4.07 + vec2(seed, 9.5)) * 2.0 - 1.0) * chaos_offset_px;
    vec2 jB = vec2(
        hash21(cellId * 5.13 + vec2(seed, 13.0)) * 2.0 - 1.0,
        hash21(cellId * 6.17 + vec2(seed, 13.5)) * 2.0 - 1.0) * chaos_offset_px;

    vec2 mA = pA + jA;
    vec2 mB = pB + jB;
    vec2 mid = (mA + mB) * 0.5;

    float boilAng = hash21(cellId + vec2(seed, 2.0)) * 6.2831853;
    vec2 boilDir = vec2(cos(boilAng), sin(boilAng));
    vec2 chord = mB - mA;
    float chordLen = length(chord);
    vec2 chordDir = chordLen > 1e-4 ? chord / chordLen : boilDir;
    float chordWeight = 1.0 - clamp(boil_angle_spread / 180.0, 0.0, 1.0);
    vec2 dir = normalize(mix(boilDir, chordDir, chordWeight));
    float halfLen = cs * max(line_length, 0.25) * 0.5;

    vec2 sA = mid - dir * halfLen;
    vec2 sB = mid + dir * halfLen;
    float maxRad = chaos_angle * 0.0174532925;
    float angA = (hash21(cellId * 7.11 + vec2(seed, 19.0)) * 2.0 - 1.0) * maxRad;
    float angB = (hash21(cellId * 8.13 + vec2(seed, 23.0)) * 2.0 - 1.0) * maxRad;
    sA = rotate2(sA - mid, angA) + mid;
    sB = rotate2(sB - mid, angB) + mid;

    float rough = line_wiggle * (0.35 + 0.1 * cs);
    return handDrawnSegment(globalPix, sA, sB, line_width, cellId, seed, rough, line_width_variation);
}

float cellHatchStrokeInk(vec2 globalPix, vec2 cellId, float cs, float seed, float dMax, float minLen, float thresh)
{
    if (!cellPassesDrawChance(cellId, seed + 131.0, hatch_draw_chance)) {
        return 0.0;
    }

    vec2 origin = (cellId + 0.5) * cs;
    float cullR = dMax + cs * 0.6;
    if (length(globalPix - origin) > cullR) {
        return 0.0;
    }
    if (hatchNearImageFrame(origin)) {
        return 0.0;
    }
    if (!hatchOriginDensityOk(origin, cs, thresh)) {
        return 0.0;
    }

    float hatchSeed = seed + 131.0;
    vec2 crossDir;
    vec2 wallA;
    vec2 wallB;

    if (pickCellStrokeChord(cellId, cs, seed, wallA, wallB)) {
        origin = (wallA + wallB) * 0.5;
        vec2 chord = wallB - wallA;
        float chordLen = length(chord);
        if (chordLen > 1e-3) {
            crossDir = vec2(-chord.y, chord.x) / chordLen;
        } else {
            float ang = hash21(cellId + vec2(hatchSeed, 1.0)) * 6.2831853;
            crossDir = vec2(cos(ang), sin(ang));
        }
    } else {
        float ang = hash21(cellId + vec2(hatchSeed, 1.0)) * 6.2831853;
        crossDir = vec2(cos(ang), sin(ang));
    }

    float spreadRad = hatch_angle_spread * 0.0174532925;
    float angJit = (hash21(cellId + vec2(hatchSeed, 4.0)) * 2.0 - 1.0) * spreadRad;
    crossDir = normalize(rotate2(crossDir, angJit));

    vec2 pA;
    vec2 pB;
    if (!hatchTryBestRay(origin, crossDir, dMax, minLen, thresh, pA, pB)) {
        return 0.0;
    }

    float strokeLen = length(pB - pA);
    if (strokeLen < minLen) {
        return 0.0;
    }
    if (hatchNearImageFrame(pA) || hatchNearImageFrame(pB)) {
        return 0.0;
    }

    vec2 mid = (pA + pB) * 0.5;
    if (edgeAtPix(mid) >= thresh * 0.8) {
        return 0.0;
    }

    vec2 segDir = (pB - pA) / strokeLen;
    vec2 perp = vec2(-segDir.y, segDir.x);
    pA += perp * ((hash21(cellId + vec2(hatchSeed, 2.0)) * 2.0 - 1.0) * hatch_offset_px);
    pB += perp * ((hash21(cellId + vec2(hatchSeed, 3.0)) * 2.0 - 1.0) * hatch_offset_px);

    if (length(pB - pA) < minLen) {
        return 0.0;
    }

    float rough = hatch_wiggle * (0.35 + 0.08 * cs);
    return handDrawnSegment(globalPix, pA, pB, hatch_width, cellId, hatchSeed, rough, hatch_width_variation);
}

void fragment() {
    vec4 src = sample_source(UV);
    vec2 uv = UV;
    vec2 pix = uv * get_uv_size();

    float cs = max(cell_size, 8.0);
    vec2 cellId = floor(pix / cs);

    float interval = max(boil_interval, 0.05);
    float seed = floor(shader_time() / interval);

    float halfLenPx = cs * max(line_length, 0.25) * 0.5;
    float minLen = max(hatch_length_px, 1.0);
    float dMax = max(hatch_max_length_px, minLen + 8.0);
    float hatchSpan = dMax + hatch_offset_px + hatch_width * 4.0;
    float lineSpan = chaos_offset_px * 2.0 + halfLenPx + line_width * 4.0;
    int lineStrengthI = int(min(ceil(lineSpan / cs) + 3.0, 16.0));
    int hatchReachI = int(min(ceil(hatchSpan / cs) + 1.0, 10.0));
    float threshH = clamp(edge_threshold, 0.01, 0.95);

    float inkLine = 0.0;
    float inkHatch = 0.0;

    for (int dy = -lineStrengthI; dy <= lineStrengthI; dy++) {
        for (int dx = -lineStrengthI; dx <= lineStrengthI; dx++) {
            float fdx = float(dx);
            float fdy = float(dy);
            vec2 nid = cellId + vec2(fdx, fdy);
            inkLine = max(inkLine, cellLineInk(pix, nid, cs, seed));
        }
    }

    if (hatch_draw_chance > 0.0) {
        for (int hy = -hatchReachI; hy <= hatchReachI; hy++) {
            for (int hx = -hatchReachI; hx <= hatchReachI; hx++) {
                float fhx = float(hx);
                float fhy = float(hy);
                vec2 nid = cellId + vec2(fhx, fhy);
                vec2 nCenter = (nid + 0.5) * cs;
                if (length(pix - nCenter) <= dMax + cs * 0.6) {
                    inkHatch = max(inkHatch, cellHatchStrokeInk(pix, nid, cs, seed, dMax, minLen, threshH));
                }
            }
        }
    }

    float thresh = clamp(edge_threshold, 0.01, 0.95);
    float edgeHere = edgeAt(uv);
    float edgeMask = mix(
        1.0,
        1.0 - smoothstep(thresh * 0.7, thresh * 1.05, edgeHere),
        clamp(contour_hold, 0.0, 1.0));

    inkLine *= edgeMask;
    inkHatch *= edgeMask;
    inkLine = smoothstep(0.08, 0.45, inkLine);
    inkHatch = smoothstep(0.06, 0.42, inkHatch);

    vec4 outCol = mix(background_color, line_color, inkLine);
    float hatchAlpha = inkHatch * hatch_color.a * hatch_opacity;
    outCol = mix(outCol, hatch_color, hatchAlpha);

    if (preserve_alpha) {
        float inkA = max(inkLine * line_color.a, hatchAlpha);
        outCol.a = mix(background_color.a, 1.0, inkA) * src.a;
        outCol.rgb = mix(outCol.rgb, background_color.rgb, 1.0 - src.a);
    }

    outCol.rgb *= fade_alpha;
    outCol.a *= fade_alpha;
    COLOR = outCol;
}

