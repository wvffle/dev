var x = 1;
let y = 2;
export function f(p) {
  p = 3;
  if (p) {
    return 'a' + y;
  } else {
    return x;
  }
}
