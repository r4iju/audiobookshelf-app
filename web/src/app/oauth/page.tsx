import type { Metadata } from "next";
import { OpenIdReturn } from "@/components/connect/openid-return";

export const metadata: Metadata = { title: "Signing in" };

/** The server sends the browser here after OpenID sign-in; the address is in the server's allowed redirect URIs. */
export default function OAuthPage() {
  return <OpenIdReturn />;
}
