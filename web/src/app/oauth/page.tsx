import type { Metadata } from "next";
import { OpenIdReturn } from "@/components/connect/openid-return";
import { initialLanguage } from "@/i18n/server";

export async function generateMetadata(): Promise<Metadata> {
  const { strings } = await initialLanguage();
  return { title: strings.WebOpenIdCompleting };
}

/** The server sends the browser here after OpenID sign-in; the address is in the server's allowed redirect URIs. */
export default function OAuthPage() {
  return <OpenIdReturn />;
}
