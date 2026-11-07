import relativeLinks from "markdownlint-rule-relative-links";

export default {
  config: {
    default: true,
    // Keep prose and tables readable in source without forced line wrapping.
    MD013: false,
    "relative-links": { root_path: "." },
  },
  customRules: [relativeLinks],
  globs: ["**/*.md"],
  ignores: [".local/**", "node_modules/**"],
};
