// The check workspace route: a thin server shell that requires a session,
// then hands over to the client-side workspace (capture needs the browser:
// WebCrypto hashing, file inputs, storage upload).
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../lib/supabase/server";
import CheckWorkspace from "./workspace";

export const dynamic = "force-dynamic";

export default async function CheckPage({ params }: { params: { id: string } }) {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect(`/signup?mode=signin&next=/work/checks/${params.id}`);
  return <CheckWorkspace />;
}
