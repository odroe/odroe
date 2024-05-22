import fs from "fs";
import yaml from "yaml";
import { defineLoader } from "vitepress";

export default defineLoader({
  watch: "../../packages/*/pubspec.yaml",
  load(watchedFiles) {
    return watchedFiles.map((path) => {
      const contents = fs.readFileSync(path, "utf-8");

      return yaml.parse(contents);
    });
  },
});
