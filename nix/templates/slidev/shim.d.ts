import type { SlideContext } from "@slidev/client/context";
import type { ShallowUnwrapRef } from "vue";
import type { SlideInfoBase } from "@slidev/types";

declare module "vue" {
  interface ComponentCustomProperties extends ShallowUnwrapRef<SlideContext> {}
}

declare module "vue-router" {
  interface RouteMeta {
    slide: SlideInfoBase | undefined;
  }
}

export {};
