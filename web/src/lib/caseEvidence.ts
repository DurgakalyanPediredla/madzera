import { supabase } from "@/lib/supabase";

const EVIDENCE_BUCKET = "case-evidence";
const MAX_FILE_BYTES = 10 * 1024 * 1024;

const ALLOWED_TYPES = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
]);

export type CaseEvidenceAttachment = {
  id: string;
  comment_id: string | null;
  file_name: string;
  file_type: string;
  file_size_bytes: number;
  created_at: string;
  uploaded_by_user_id: string;
  uploaded_by_name: string;
};

export async function getCaseEvidence(
  caseId: string,
  lockToken: string
): Promise<CaseEvidenceAttachment[]> {
  const { data, error } = await supabase.rpc("get_employee_case_evidence", {
    p_case_id: caseId,
    p_lock_token: lockToken,
  });

  if (error) {
    throw new Error(`Unable to retrieve case evidence: ${error.message}`);
  }

  return (data ?? []) as CaseEvidenceAttachment[];
}

export async function downloadCaseEvidence(
  caseId: string,
  lockToken: string,
  attachmentId: string
): Promise<Blob> {
  const { data: storagePath, error: pathError } = await supabase.rpc(
    "get_employee_case_evidence_download_path",
    {
      p_attachment_id: attachmentId,
      p_case_id: caseId,
      p_lock_token: lockToken,
    }
  );

  if (pathError || !storagePath) {
    throw new Error(
      `Unable to authorise evidence download: ${
        pathError?.message ?? "No storage path returned"
      }`
    );
  }

  const { data, error } = await supabase.storage
    .from(EVIDENCE_BUCKET)
    .download(storagePath);

  if (error || !data) {
    throw new Error(
      `Unable to download evidence: ${error?.message ?? "No file returned"}`
    );
  }

  return data;
}

export type CaseEvidenceUploadReservation = {
  reservation_id: string;
  file_name: string;
  reservation_status: "pending" | "expired" | "completed";
  created_at: string;
  expires_at: string;
};

export async function listEmployeeCaseEvidenceUploadReservations(
  caseId: string,
  lockToken: string
): Promise<CaseEvidenceUploadReservation[]> {
  const { data, error } = await supabase.rpc(
    "list_employee_case_evidence_upload_reservations",
    {
      p_case_id: caseId,
      p_lock_token: lockToken,
    }
  );

  if (error) {
    throw new Error(
      `Unable to discover evidence upload reservations: ${error.message}`
    );
  }

  if (!Array.isArray(data)) {
    throw new Error("Evidence reservation discovery returned an invalid response.");
  }

  for (const record of data) {
    if (
      !record ||
      typeof record.reservation_id !== "string" ||
      typeof record.file_name !== "string" ||
      !["pending", "expired", "completed"].includes(
        record.reservation_status
      ) ||
      typeof record.created_at !== "string" ||
      typeof record.expires_at !== "string"
    ) {
      throw new Error("Evidence reservation discovery returned invalid data.");
    }
  }

  return data as CaseEvidenceUploadReservation[];
}

export type CaseEvidenceUploadRecoveryStatus = {
  reservation_status: "pending" | "expired" | "completed";
  attachment_id: string | null;
};

export async function getCaseEvidenceUploadRecoveryStatus(
  caseId: string,
  lockToken: string,
  reservationId: string
): Promise<CaseEvidenceUploadRecoveryStatus> {
  const { data, error } = await supabase.rpc(
    "get_case_evidence_upload_recovery_status",
    {
      p_reservation_id: reservationId,
      p_case_id: caseId,
      p_lock_token: lockToken,
    }
  );

  if (error) {
    throw new Error(
      `Unable to check evidence upload status: ${error.message}`
    );
  }

  const result = Array.isArray(data) ? data[0] : data;

  if (
    !result ||
    !["pending", "expired", "completed"].includes(
      result.reservation_status
    ) ||
    (
      result.reservation_status === "completed" &&
      typeof result.attachment_id !== "string"
    )
  ) {
    throw new Error("Evidence recovery returned an invalid response.");
  }

  return result as CaseEvidenceUploadRecoveryStatus;
}

export class EvidenceUploadNeedsReviewError extends Error {
  readonly reservationId: string;

  constructor(message: string, reservationId: string) {
    super(message);
    this.name = "EvidenceUploadNeedsReviewError";
    this.reservationId = reservationId;
  }
}

export class EvidenceReservationNeedsReviewError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EvidenceReservationNeedsReviewError";
  }
}

type UploadCaseEvidenceArgs = {
  caseId: string;
  lockToken: string;
  commentId: string | null;
  file: File;
};

export async function uploadCaseEvidence({
  caseId,
  lockToken,
  commentId,
  file,
}: UploadCaseEvidenceArgs): Promise<string> {
  if (
    !ALLOWED_TYPES.has(file.type) ||
    file.size < 1 ||
    file.size > MAX_FILE_BYTES ||
    file.name.length < 1 ||
    file.name.length > 255 ||
    /[\/\\\x00-\x1f\x7f]/.test(file.name)
  ) {
    throw new Error(`Invalid evidence file: ${file.name}`);
  }

  let reservation: unknown;
  let reservationError: { message: string } | null = null;

  try {
    const result = await supabase.rpc("prepare_case_evidence_upload", {
      p_case_id: caseId,
      p_lock_token: lockToken,
      p_file_name: file.name,
      p_file_type: file.type,
      p_file_size_bytes: file.size,
    });

    reservation = result.data;
    reservationError = result.error;
  } catch (cause) {
    throw new EvidenceReservationNeedsReviewError(
      `Evidence reservation response was interrupted for ${file.name}. ` +
        `Do not retry until outstanding reservations have been checked. ` +
        `${cause instanceof Error ? cause.message : ""}`
    );
  }

  if (reservationError) {
    throw new EvidenceReservationNeedsReviewError(
      `Evidence reservation outcome is unconfirmed for ${file.name}. ` +
        `Do not retry until outstanding reservations have been checked. ` +
        reservationError.message
    );
  }

  const prepared = Array.isArray(reservation) ? reservation[0] : reservation;

  if (
    !prepared ||
    typeof prepared !== "object" ||
    !("reservation_id" in prepared) ||
    typeof prepared.reservation_id !== "string" ||
    !("storage_path" in prepared) ||
    typeof prepared.storage_path !== "string" ||
    !prepared.reservation_id ||
    !prepared.storage_path
  ) {
    throw new EvidenceReservationNeedsReviewError(
      "Evidence reservation response was incomplete. " +
        "Do not retry until outstanding reservations have been checked."
    );
  }

  let uploadResult: Awaited<ReturnType<
    ReturnType<typeof supabase.storage.from>["upload"]
  >>;

  try {
    uploadResult = await supabase.storage
      .from(EVIDENCE_BUCKET)
      .upload(prepared.storage_path, file, {
        contentType: file.type,
        upsert: false,
      });
  } catch (cause) {
    throw new EvidenceUploadNeedsReviewError(
      `Storage upload outcome is uncertain for ${file.name}. ` +
      `Do not retry automatically. ${cause instanceof Error ? cause.message : ""}`,
      prepared.reservation_id,
    );
  }

  if (uploadResult.error) {
    throw new EvidenceUploadNeedsReviewError(
      `Storage upload failed or its outcome is uncertain for ${file.name}. ` +
      `Do not retry automatically. ${uploadResult.error.message}`,
      prepared.reservation_id,
    );
  }

  let attachmentId: string | null = null;
  let finaliseError: { message: string } | null = null;

  try {
    const result = await supabase.rpc(
      "finalise_case_evidence_upload",
      {
        p_reservation_id: prepared.reservation_id,
        p_lock_token: lockToken,
        p_comment_id: commentId,
      }
    );

    attachmentId = result.data;
    finaliseError = result.error;
  } catch (cause) {
    throw new EvidenceUploadNeedsReviewError(
      `File ${file.name} reached Storage, but the finalisation response ` +
      `was interrupted. Do not re-upload until its status is checked. ` +
      `${cause instanceof Error ? cause.message : ""}`,
      prepared.reservation_id,
    );
  }

  if (finaliseError || !attachmentId) {
    throw new EvidenceUploadNeedsReviewError(
      `File ${file.name} reached Storage but finalisation is unconfirmed: ${
        finaliseError?.message ?? "Missing attachment ID"
      }. Do not re-upload until an administrator checks its status.`,
      prepared.reservation_id,
    );
  }

  return attachmentId;
}
