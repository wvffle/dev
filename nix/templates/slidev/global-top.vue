<script setup lang="ts">
import { computed } from "vue";
import { useSlideContext } from "@slidev/client";
import type { SlideInfo } from "@slidev/types";

const { $nav } = useSlideContext();

const titles = computed(() => {
  const nav = $nav.value;
  const activeIndex = nav.currentSlideNo - 1;
  return nav.slides
    .map((slide, index, array) => {
      const { title = null } = slide.meta.slide ?? {};

      return index === 0 || title !== array[index - 1].meta.slide?.title
        ? { title, index }
        : null;
    })
    .filter(<T>(value: T | null): value is T => value !== null)
    .filter((_, index, array) => index !== 0 && index !== array.length - 1)
    .map((slide, index, slides) => {
      const isFuture =
        index === slides.length - 1 || activeIndex < slides[index + 1].index;
      const isCurrent = isFuture && activeIndex >= slide.index;
      return { ...slide, isCurrent };
    });
});
</script>

<template>
  <header v-if="$nav.currentSlideNo !== 1 && $nav.currentSlideNo !== $nav.slides.at(-1)?.no"
    class="absolute top-0 right-0 p-2 w-full bg-white">
    <ul class="flex justify-evenly text-xs">
      <li v-for="title in titles" :key="title.index" :class="{ 'opacity-50': !title.isCurrent }">
        {{ title.title }}
      </li>
    </ul>
  </header>
</template>
