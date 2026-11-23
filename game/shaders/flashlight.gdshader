// 手电光锥（扇形，不是圆）—— 参照目标帧：一道三角光锥打到地面，圈外近黑
//
// 依据 godot-shaders-basics 的硬规矩：
//   ① 动态选择一律 mix / smoothstep，不用 if/else
//   ② 颜色 uniform 带 source_color（token 是 source_color，不是 hint_source_color）
//   ③ TIME 配 speed multiplier
//
// 做法：整屏乘一张 mask。角度与距离各自 smoothstep 后相乘 ——
// 得到「有方向的锥」而不是「一圈光」。

shader_type canvas_item;
render_mode blend_mul;

uniform vec2 light_pos_px = vec2(96.0, 160.0);   // 屏幕像素坐标，由场景每帧写入
uniform float radius_px = 240.0;
uniform float softness_px = 48.0;
uniform float cone_dir = 0.0;                    // 弧度，0 = 朝右
uniform float cone_half = 0.42;                  // 半角
uniform float cone_feather = 0.16;               // 锥边羽化
uniform float flicker_speed = 0.9;

uniform vec4 outside_tint : source_color = vec4(0.42, 0.46, 0.58, 1.0);
uniform vec4 inside_tint : source_color = vec4(1.28, 1.02, 0.62, 1.0);

void fragment() {
	vec2 d = FRAGCOORD.xy - light_pos_px;
	float dist = length(d);

	// 角度差折回 [-PI, PI]，避免在 ±PI 处断裂
	float diff = atan(d.y, d.x) - cone_dir;
	float ang = abs(atan(sin(diff), cos(diff)));

	float by_angle = 1.0 - smoothstep(cone_half - cone_feather, cone_half, ang);
	float by_dist = 1.0 - smoothstep(radius_px - softness_px, radius_px, dist);

	float breathe = 1.0 + 0.012 * sin(TIME * flicker_speed * 6.2831853);
	float lit = by_angle * by_dist * breathe;

	vec3 c = mix(outside_tint.rgb, inside_tint.rgb, lit);
	COLOR = vec4(c, 1.0);
}
