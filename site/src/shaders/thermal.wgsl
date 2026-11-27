// Thermal ("inferno") palette shared by the effects: deep violet → magenta → red-orange → amber.
export fn thermal(x: f32) -> vec3f {
  let c0 = vec3f(0.196, 0.039, 0.369);
  let c1 = vec3f(0.471, 0.110, 0.427);
  let c2 = vec3f(0.737, 0.216, 0.329);
  let c3 = vec3f(0.929, 0.412, 0.145);
  let c4 = vec3f(0.984, 0.714, 0.102);
  let t = clamp(x, 0.0, 1.0) * 4.0;
  if (t < 1.0) { return mix(c0, c1, t); }
  if (t < 2.0) { return mix(c1, c2, t - 1.0); }
  if (t < 3.0) { return mix(c2, c3, t - 2.0); }
  return mix(c3, c4, t - 3.0);
}
