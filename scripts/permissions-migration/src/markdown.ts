export default {
  row(items: string[]) {
    return `| ${items.join(" | ")} |`;
  },
  header(columns: string[]) {
    return [
      this.row(columns),
      this.row(Array(columns.length).fill("---")),
    ].join("\n");
  },
  bold(text: string) {
    return `**${text}**`;
  },
  label(text: string) {
    return `\`${text}\``;
  },
  empty() {
    return "∅";
  },
  roleName(rawRoleName: string) {
    const roleNameParts = rawRoleName.split("_");
    return roleNameParts.join(" ");
  },
  modified(text: string) {
    return `⚠️ **${text}**`;
  },
  unchanged(text: string) {
    return `${text}`;
  },
};
