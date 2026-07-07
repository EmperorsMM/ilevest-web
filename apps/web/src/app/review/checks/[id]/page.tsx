// The bench route: session required, then the client-side bench (the sealing
// ceremony needs typed confirmation and signed-URL evidence viewing).
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../lib/supabase/server";
import ReviewBench from "./bench";

export const dynamic = "force-dynamic";

export default async function BenchPage({ params }: { params: { id: string } }) {
  const supabase = createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect(`/signup?mode=signin&next=/review/checks/${params.id}`);
  return <ReviewBench />;
}
