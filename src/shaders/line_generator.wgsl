
@group(0) @binding(2) var<uniform> thickness: f32;

@group(0) @binding(0) var<storage, read_write> points: array<vec2<f32>>;
@group(0) @binding(1) var<storage, read_write> lines: array<vec2<f32>>;

@compute @workgroup_size(1) fn main(@builtin(workgroup_id) id: vec3<u32>) {
	var i = id[0] + id[1] + id[2] - 3;
	var a1 = points[i];
	var a2 = points[i+1];
	var diff = normalize(a2 - a1);
	var norm = vec2(-diff.y, diff.x);
	lines[i * 6 + 0] = a1 - norm * thickness/2;
	lines[i * 6 + 1] = a2 - norm * thickness/2;
	lines[i * 6 + 2] = a2 + norm * thickness/2;
	lines[i * 6 + 3] = a2 + norm * thickness/2;
	lines[i * 6 + 4] = a1 + norm * thickness/2;
	lines[i * 6 + 5] = a1 - norm * thickness/2;
}
