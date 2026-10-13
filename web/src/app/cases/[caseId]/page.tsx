
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import CaseActivityEditor from "./CaseActivityEditor";

type CasePageProps = {
  params: Promise<{ caseId: string }>;
};

const demoCaseDetails = {
  "CASE-1001": {
    customer: "ABC Imports",
    createdBy: "John Davis",
    enquiryType: "Customer enquiry",
    subject: "Customs documentation enquiry",
    status: "Open",
    received: "12 October 2026, 09:42",
    team: "Customs Operations",
    assignedTo: "Sarah Mitchell",
    description:
      "The customer has requested clarification about the documentation required for an upcoming import shipment.",
  },
  "CASE-1002": {
    customer: "Seabrook Trading",
    createdBy: "Emma Clarke",
    enquiryType: "Customer enquiry",
    subject: "Shipment clearance update",
    status: "In progress",
    received: "12 October 2026, 09:18",
    team: "Customs Operations",
    assignedTo: "Sarah Mitchell",
    description:
      "The customer has requested an update on the progress of their shipment clearance.",
  },
  "CASE-1003": {
    customer: "Westport Logistics",
    createdBy: "Sarah Mitchell",
    enquiryType: "Internal enquiry",
    subject: "Missing invoice information",
    status: "Pending customer",
    received: "11 October 2026, 16:25",
    team: "Customs Operations",
    assignedTo: "Sarah Mitchell",
    description:
      "Additional commercial invoice information is required before the enquiry can be progressed.",
  },
};

const demoCaseActivities = {
  "CASE-1001": [
    {
      id: 1,
      employee: "Sarah Mitchell",
      date: "12 October 2026, 10:15",
      team: "Customs Operations",
      action: "Work update",
      comment:
        "Reviewed the customer's documentation enquiry and identified additional information required before processing can continue.",
      attachment: "Documentation_Checklist.pdf",
    },
    {
      id: 2,
      employee: "John Davis",
      date: "12 October 2026, 09:55",
      team: "Customer Services",
      action: "Handover to Customs Operations",
      comment:
        "Initial enquiry reviewed and routed to Customs Operations for documentation assessment.",
      attachment: null,
    },
  ],
  "CASE-1002": [],
  "CASE-1003": [],
};

async function CaseDetailsContent({ params }: CasePageProps) {
  const { caseId } = await params;

  const caseDetails =
    demoCaseDetails[caseId as keyof typeof demoCaseDetails];

  if (!caseDetails) {
    notFound();
  }

  const caseActivities =
    demoCaseActivities[caseId as keyof typeof demoCaseActivities];

  return (
    <main className="min-h-screen bg-[#FAF9F6] px-6 py-8 text-[#39352F]">
      <div className="mx-auto max-w-6xl">
        <Link
          href="/cases"
          className="text-sm text-[#51483F] hover:underline"
        >
          ← Back to cases
        </Link>

        {/* Case header */}
        <div className="mt-6 pb-4">
          <h1 className="text-2xl font-semibold">
            {caseId}
          </h1>

          <h2 className="mt-2 text-lg font-medium">
            {caseDetails.subject}
          </h2>

          <p className="mt-2 text-sm text-[#756B60]">
            {caseDetails.customer} · {caseDetails.team}
          </p>

          <p className="mt-1 text-xs text-[#756B60]">
            Demonstration environment
          </p>
        </div>

        {/* Case navigation and ownership controls */}
        <div className="mt-4 flex flex-col gap-4 border-b border-[#D8CBB8] lg:flex-row lg:items-center lg:justify-between">
          {/* Left: case navigation */}
          <nav
            aria-label="Case sections"
            className="flex gap-6 self-start"
          >
            <span
              aria-current="page"
              className="border-b-2 border-[#51483F] px-1 pb-3 text-sm font-semibold text-[#39352F]"
            >
              Case Record
            </span>

            <span className="px-1 pb-3 text-sm text-[#756B60]">
              Audit History
            </span>
          </nav>

          {/* Right: status, owner and work controls */}
          <div className="flex flex-wrap items-center gap-x-6 gap-y-3 pb-3">
            <div>
              <p className="text-xs text-[#756B60]">
                Status
              </p>

              <p className="mt-1 text-sm font-semibold text-[#39352F]">
                {caseDetails.status}
              </p>
            </div>

            <div>
              <p className="text-xs text-[#756B60]">
                Current owner
              </p>

              <p className="mt-1 text-sm font-semibold text-[#39352F]">
                Unclaimed
              </p>
            </div>

            <button
              type="button"
              disabled
              title="Available after secure case ownership and audit logging are connected"
              className="cursor-not-allowed rounded-md bg-[#51483F] px-4 py-2 text-sm font-medium text-white opacity-50"
            >
              Start Work
            </button>
          </div>
        </div>

        {/* Case information */}
        <section className="mt-4 overflow-hidden rounded-lg border border-[#D8CBB8] bg-white">
          <div className="border-b border-[#D8CBB8] bg-[#EAE4D9] px-5 py-3">
            <h3 className="text-sm font-semibold">
              Case Information
            </h3>
          </div>

          <dl className="space-y-5 px-6 py-6">
            {[
              ["Created by", caseDetails.createdBy],
              ["Created on", caseDetails.received],
              ["Customer", caseDetails.customer],
              ["Enquiry type", caseDetails.enquiryType],
              ["Assigned team", caseDetails.team],
              ["Initially assigned to", caseDetails.assignedTo],
            ].map(([label, value]) => (
              <div key={label}>
                <dt className="text-xs font-medium text-[#756B60]">
                  {label}
                </dt>

                <dd className="mt-1 text-sm font-medium text-[#39352F]">
                  {value}
                </dd>
              </div>
            ))}

            <div className="border-t border-[#EAE4D9] pt-5">
              <dt className="text-xs font-medium text-[#756B60]">
                Description / Initial comment
              </dt>

              <dd className="mt-2 whitespace-pre-wrap text-sm leading-6 text-[#39352F]">
                {caseDetails.description}
              </dd>
            </div>
          </dl>
        </section>

        {/* Case activity */}
        <section className="mt-8">
          <div className="grid grid-cols-[1fr_auto] items-center gap-4 border-b border-[#D8CBB8] pb-3">
            <h3 className="text-lg font-semibold text-[#39352F]">
              Case Activity
            </h3>

            <CaseActivityEditor />
          </div>

          {/* Existing case activity history */}
          <div className="mt-5 space-y-5">
            {caseActivities.length === 0 ? (
              <p className="py-6 text-sm text-[#756B60]">
                No case activity recorded yet.
              </p>
            ) : (
              caseActivities.map((activity) => (
                <article
                  key={activity.id}
                  className="border-b border-[#EAE4D9] pb-5"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <p className="text-sm font-semibold">
                      {activity.employee}
                    </p>

                    <time className="text-xs text-[#756B60]">
                      {activity.date}
                    </time>
                  </div>

                  <p className="mt-1 text-xs text-[#756B60]">
                    {activity.team} · {activity.action}
                  </p>

                  <p className="mt-3 text-sm leading-7">
                    {activity.comment}
                  </p>

                  {activity.attachment && (
                    <div className="mt-3 text-sm text-[#51483F]">
                      <span className="font-medium">
                        Attachment:
                      </span>{" "}
                      {activity.attachment}
                    </div>
                  )}
                </article>
              ))
            )}
          </div>
        </section>
      </div>
    </main>
  );
}

export default function CaseDetailsPage({
  params,
}: CasePageProps) {
  return (
    <Suspense
      fallback={
        <main className="min-h-screen bg-[#FAF9F6] px-6 py-8 text-[#39352F]">
          <p className="text-sm text-[#756B60]">
            Loading case details...
          </p>
        </main>
      }
    >
      <CaseDetailsContent params={params} />
    </Suspense>
  );
}
