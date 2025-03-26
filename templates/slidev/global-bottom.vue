<template>
  <footer v-if="$nav.currentSlideNo !== 1" class="absolute right-0 bottom-0 left-0 p-2">
    {{ $nav.currentPage }} / {{ $nav.total }}
  </footer>
</template>
