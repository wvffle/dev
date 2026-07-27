import { Thing } from './thing';
interface Local {
  a: number;
}
const n: number = 5;
const arr: Array<string> = [];
export function f(x: string) {
  return x!;
}
export type Alias = Thing;
export { Local, n, arr };
