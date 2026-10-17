export const instant = false;

import CaseWorkspace from "./CaseWorkspace";

type CasePageProps = {
  params: Promise<{ caseId: string }>;
};

export default async function CaseDetailsPage({
  params,
}: CasePageProps) {
  const { caseId } = await params;

  return <CaseWorkspace caseId={caseId} />;
}
