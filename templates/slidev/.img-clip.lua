return {
  default = {
    dir_path = "public"
  },
  filetypes = {
    markdown = {
      template = "![$CURSOR](/$FILE_NAME)",
      download_images = true
    }
  }
}
