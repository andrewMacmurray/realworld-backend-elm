import { z } from "zod";

const Schema = z.object({
  POSTGRES_URL: z.string().min(10),
  JWT_SECRET: z.string().min(15),
  NODE_ENV: z.enum(["development", "production"]).default("development"),
});

export function validate(): z.infer<typeof Schema> {
  return Schema.parse(process.env);
}

export const env: z.infer<typeof Schema> = validate();
