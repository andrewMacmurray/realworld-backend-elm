export function flatten(obj: {
  [key: string]: string[] | string | undefined;
}): {
  [key: string]: string;
} {
  return Object.fromEntries(
    Object.entries(obj).map(([k, v]) => {
      if (typeof v === "string") {
        return [k, v];
      } else if (v === undefined) {
        return [k, ""];
      } else {
        return [k, v.join(",")];
      }
    })
  );
}
