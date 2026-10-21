"use client";

import { useRef, useState } from "react";
import {
  clearEvidenceRecovery,
  readEvidenceRecoveries,
  saveEvidenceRecovery,
  type StoredEvidenceRecovery,
} from "@/lib/caseEvidenceRecovery";
import {
  EvidenceReservationNeedsReviewError,
  EvidenceUploadNeedsReviewError,
  getCaseEvidenceUploadRecoveryStatus,
  listEmployeeCaseEvidenceUploadReservations,
  uploadCaseEvidence,
  type CaseEvidenceUploadReservation,
} from "@/lib/caseEvidence";

type CaseActivityEditorProps = {
  onSave: (comment: string) => Promise<string>;
  onEvidenceUploaded: () => void;
  onEvidenceUploadActiveChange: (active: boolean) => void;
  caseId: string;
  lockToken: string;
  existingCommentId?: string | null;
};

export default function CaseActivityEditor({
  onSave,
  onEvidenceUploaded,
  onEvidenceUploadActiveChange,
  caseId,
  lockToken,
  existingCommentId = null,
}: CaseActivityEditorProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [comment, setComment] = useState("");
  const [evidenceFiles, setEvidenceFiles] = useState<File[]>([]);
  const [savedCommentId, setSavedCommentId] = useState<string | null>(null);
  const targetCommentId = existingCommentId ?? savedCommentId;
  const evidenceOnlyMode = existingCommentId !== null;
  const [uploadNeedsReview, setUploadNeedsReview] = useState(false);
  const [uncertainUpload, setUncertainUpload] = useState<{
    reservationId: string;
    fileName: string;
    file: File;
  } | null>(null);
  const [restoredRecoveries, setRestoredRecoveries] =
    useState<StoredEvidenceRecovery[]>([]);
  const [databaseRecoveries, setDatabaseRecoveries] =
    useState<CaseEvidenceUploadReservation[]>([]);
  const [discoveringRecoveries, setDiscoveringRecoveries] = useState(false);


  const [checkingUpload, setCheckingUpload] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const savingRef = useRef(false);

  function closeEditor() {
    if (savingRef.current || checkingUpload || discoveringRecoveries) return;

    if (uploadNeedsReview || uncertainUpload) {
      setError(
        "This evidence upload requires review. Check its status before " +
        "closing the editor. Do not upload the file again."
      );
      return;
    }

    if ((savedCommentId || evidenceOnlyMode) && evidenceFiles.length > 0) {
      const confirmed = window.confirm(
        "Some evidence files are still selected but have not been attached. " +
        "Closing discards the pending selection, not the existing activity. " +
        "Close anyway?"
      );
      if (!confirmed) return;
    }
    setIsOpen(false);
    setComment("");
    setEvidenceFiles([]);
    setSavedCommentId(null);
    setUploadNeedsReview(false);
    setUncertainUpload(null);
    setError(null);
  }

  async function openEditorWithRecovery() {
    if (discoveringRecoveries || savingRef.current) return;

    let browserRecords: StoredEvidenceRecovery[];

    try {
      browserRecords = readEvidenceRecoveries(caseId);
    } catch {
      setRestoredRecoveries([]);
      setDatabaseRecoveries([]);
      setUploadNeedsReview(true);
      setError(
        "Unable to check previous evidence uploads in browser storage. " +
          "Saving is blocked until recovery can be verified."
      );
      setIsOpen(true);
      return;
    }

    setRestoredRecoveries(browserRecords);
    setDatabaseRecoveries([]);
    setUploadNeedsReview(true);
    setDiscoveringRecoveries(true);
    setError(null);
    setIsOpen(true);

    try {
      const reservations = await listEmployeeCaseEvidenceUploadReservations(
        caseId,
        lockToken
      );

      const unresolved = reservations.filter(
        (record) =>
          record.reservation_status === "pending" ||
          record.reservation_status === "expired"
      );

      setDatabaseRecoveries(unresolved);
      setUploadNeedsReview(
        browserRecords.length > 0 || unresolved.length > 0
      );
    } catch (cause) {
      setUploadNeedsReview(true);
      setError(
        cause instanceof Error
          ? cause.message
          : "Unable to verify previous evidence uploads."
      );
    } finally {
      setDiscoveringRecoveries(false);
    }
  }

  async function retryRecoveryCheck() {
    if (savingRef.current || checkingUpload || discoveringRecoveries) return;

    setUploadNeedsReview(true);
    setDiscoveringRecoveries(true);
    setError(null);

    try {
      readEvidenceRecoveries(caseId);

      const reservations = await listEmployeeCaseEvidenceUploadReservations(
        caseId,
        lockToken
      );

      const unresolvedDatabase = reservations.filter(
        (record) =>
          record.reservation_status === "pending" ||
          record.reservation_status === "expired"
      );

      // Recheck browser storage after the asynchronous database request.
      const latestBrowserRecords = readEvidenceRecoveries(caseId);

      setRestoredRecoveries(latestBrowserRecords);
      setDatabaseRecoveries(unresolvedDatabase);

      const requiresReview =
        latestBrowserRecords.length > 0 ||
        unresolvedDatabase.length > 0 ||
        uncertainUpload !== null;

      setUploadNeedsReview(requiresReview);

      setError(
        requiresReview
          ? "Outstanding evidence reservations still require review. " +
              "Do not upload these files again until their status is resolved."
          : "Recovery verification completed. No outstanding evidence " +
              "reservations were found. You may continue saving."
      );
    } catch (cause) {
      setUploadNeedsReview(true);
      setError(
        cause instanceof Error
          ? "Recovery verification failed: " + cause.message
          : "Recovery verification failed. Saving remains blocked."
      );
    } finally {
      setDiscoveringRecoveries(false);
    }
  }

  async function checkDatabaseUploadStatus(reservationId: string) {
    if (savingRef.current || checkingUpload || discoveringRecoveries) return;

    setCheckingUpload(true);
    setError(null);

    try {
      const result = await getCaseEvidenceUploadRecoveryStatus(
        caseId,
        lockToken,
        reservationId
      );

      if (
        result.reservation_status === "completed" &&
        result.attachment_id
      ) {
        clearEvidenceRecovery(reservationId);

        const remainingBrowser = readEvidenceRecoveries(caseId);
        const remainingDatabase = databaseRecoveries.filter(
          (record) => record.reservation_id !== reservationId
        );

        const matchesActiveUpload =
          uncertainUpload?.reservationId === reservationId;

        if (matchesActiveUpload && uncertainUpload) {
          setEvidenceFiles((files) =>
            files.filter((file) => file !== uncertainUpload.file)
          );
          setUncertainUpload(null);
        }

        setRestoredRecoveries(remainingBrowser);
        setDatabaseRecoveries(remainingDatabase);

        setUploadNeedsReview(
          remainingBrowser.length > 0 ||
            remainingDatabase.length > 0 ||
            (uncertainUpload !== null && !matchesActiveUpload)
        );

        onEvidenceUploaded();
        setError(
          "The reservation was confirmed complete. " +
            "No duplicate evidence upload was performed."
        );
      } else {
        setError(
          result.reservation_status === "expired"
            ? "This reservation has expired. Its Storage contents require review."
            : "This reservation remains pending. Its Storage contents require review."
        );
      }
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Unable to verify the evidence reservation."
      );
    } finally {
      setCheckingUpload(false);
    }
  }

  async function checkRestoredUploadStatus(reservationId: string) {
    if (savingRef.current || checkingUpload || discoveringRecoveries) return;

    setCheckingUpload(true);
    setError(null);

    try {
      const result = await getCaseEvidenceUploadRecoveryStatus(
        caseId,
        lockToken,
        reservationId
      );

      if (result.reservation_status === "completed" && result.attachment_id) {
        clearEvidenceRecovery(reservationId);

        const remaining = readEvidenceRecoveries(caseId);
        setRestoredRecoveries(remaining);

        const remainingDatabase = databaseRecoveries.filter(
          (record) => record.reservation_id !== reservationId
        );
        const matchesActiveUpload =
          uncertainUpload?.reservationId === reservationId;

        if (matchesActiveUpload && uncertainUpload) {
          setEvidenceFiles((files) =>
            files.filter((file) => file !== uncertainUpload.file)
          );
          setUncertainUpload(null);
        }

        setDatabaseRecoveries(remainingDatabase);

        setUploadNeedsReview(
          remaining.length > 0 ||
            remainingDatabase.length > 0 ||
            (uncertainUpload !== null && !matchesActiveUpload)
        );

        onEvidenceUploaded();
        setError(
          "This reservation was confirmed complete. " +
          "Its recovery record has been cleared without uploading another file."
        );
      } else {
        setError(
          result.reservation_status === "expired"
            ? "This reservation has expired. Its Storage contents require review."
            : "This reservation remains pending. Its Storage contents require review."
        );
      }
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Unable to check the saved reservation."
      );
    } finally {
      setCheckingUpload(false);
    }
  }

  async function checkUploadStatus() {
    if (
      !uncertainUpload ||
      savingRef.current ||
      checkingUpload ||
      discoveringRecoveries
    ) return;

    setCheckingUpload(true);
    setError(null);

    try {
      const result = await getCaseEvidenceUploadRecoveryStatus(
        caseId,
        lockToken,
        uncertainUpload.reservationId
      );

      if (result.reservation_status === "completed" && result.attachment_id) {
        setEvidenceFiles((files) =>
          files.filter((file) => file !== uncertainUpload.file)
        );
        clearEvidenceRecovery(uncertainUpload.reservationId);
        const remaining = readEvidenceRecoveries(caseId);
        setRestoredRecoveries(remaining);
        const remainingDatabase = databaseRecoveries.filter(
          (record) =>
            record.reservation_id !== uncertainUpload.reservationId
        );
        setDatabaseRecoveries(remainingDatabase);
        setUncertainUpload(null);
        setUploadNeedsReview(
          remaining.length > 0 || remainingDatabase.length > 0
        );
        onEvidenceUploaded();
        setError(
          "The original evidence upload was confirmed complete. " +
          "No duplicate upload was performed. You may now save any remaining files."
        );
      } else {
        setError(
          result.reservation_status === "expired"
            ? "This reservation has expired. Its Storage contents must " +
              "be reviewed before another upload is attempted."
            : "This reservation is pending. Its Storage contents must " +
              "be reviewed before another upload is attempted."
        );
      }
    } catch (cause) {
      setError(
        cause instanceof Error
          ? cause.message
          : "Unable to check evidence upload status."
      );
    } finally {
      setCheckingUpload(false);
    }
  }

  async function saveActivity() {
    if (
      savingRef.current ||
      checkingUpload ||
      discoveringRecoveries ||
      uploadNeedsReview
    ) return;

    // Claim the Save operation before any asynchronous database request.
    savingRef.current = true;
    setSaving(true);

    let unresolved: StoredEvidenceRecovery[];

    try {
      unresolved = readEvidenceRecoveries(caseId);
    } catch {
      setUploadNeedsReview(true);
      setError(
        "Unable to check previous evidence uploads in browser storage. " +
          "Saving is blocked until recovery can be verified."
      );
      savingRef.current = false;
      setSaving(false);
      return;
    }

    if (unresolved.length > 0) {
      setRestoredRecoveries(unresolved);
      setUploadNeedsReview(true);
      setError(
        "Previous evidence uploads require review before saving. " +
        "Check their reservation status; do not upload the files again."
      );
      savingRef.current = false;
      setSaving(false);
      return;
    }

    // Recheck the database before saving, not just when opening the editor.
    // An unresolved reservation must never be silently treated as absent.

    setDiscoveringRecoveries(true);

    try {
      const reservations = await listEmployeeCaseEvidenceUploadReservations(
        caseId,
        lockToken
      );

      const unresolvedDatabase = reservations.filter(
        (record) =>
          record.reservation_status === "pending" ||
          record.reservation_status === "expired"
      );

      const unresolvedBrowser = readEvidenceRecoveries(caseId);

      setDatabaseRecoveries(unresolvedDatabase);
      setRestoredRecoveries(unresolvedBrowser);

      if (
        unresolvedDatabase.length > 0 ||
        unresolvedBrowser.length > 0
      ) {
        setUploadNeedsReview(true);
        setError(
          "Previous evidence uploads require review before saving. " +
            "Check their reservation status; do not upload the files again."
        );
        savingRef.current = false;
        setSaving(false);
        return;
      }
    } catch (cause) {
      setUploadNeedsReview(true);
      setError(
        cause instanceof Error
          ? cause.message
          : "Unable to verify previous evidence uploads. Saving is blocked."
      );
      savingRef.current = false;
      setSaving(false);
      return;
    } finally {
      setDiscoveringRecoveries(false);
    }

    const body = comment.trim();

    if (
      !targetCommentId &&
      (body.length > 10000 || (!body && evidenceFiles.length === 0))
    ) {
      setError("Enter a work update or select at least one evidence file.");
      savingRef.current = false;
      setSaving(false);
      return;
    }

    setError(null);
    let activeEvidenceFile: File | null = null;

    try {
      let commentId = targetCommentId;

      if (!commentId && body) {
        if (evidenceOnlyMode) {
          throw new Error("An existing activity comment is required for evidence upload.");
        }

        commentId = await onSave(body);
        setSavedCommentId(commentId);
      }

      if (evidenceFiles.length > 0) {
        onEvidenceUploadActiveChange(true);
      }

      for (const file of evidenceFiles) {
        activeEvidenceFile = file;

        // Verify reservations again before each individual file.
        let reservations: CaseEvidenceUploadReservation[];

        try {
          reservations = await listEmployeeCaseEvidenceUploadReservations(
            caseId,
            lockToken
          );
        } catch (cause) {
          throw new EvidenceReservationNeedsReviewError(
            "Unable to verify outstanding evidence reservations before " +
              `uploading ${file.name}. Saving remains blocked. ` +
              (cause instanceof Error ? cause.message : "")
          );
        }

        const unresolvedReservations = reservations.filter(
          (record) =>
            record.reservation_status === "pending" ||
            record.reservation_status === "expired"
        );

        if (unresolvedReservations.length > 0) {
          setDatabaseRecoveries(unresolvedReservations);
          throw new EvidenceReservationNeedsReviewError(
            "An outstanding evidence reservation was found before " +
              `uploading ${file.name}. Review its status before retrying.`
          );
        }

        let browserRecoveries: StoredEvidenceRecovery[];

        try {
          browserRecoveries = readEvidenceRecoveries(caseId);
        } catch {
          throw new EvidenceReservationNeedsReviewError(
            "Unable to verify browser evidence recovery records. " +
              "Saving remains blocked."
          );
        }

        if (browserRecoveries.length > 0) {
          setRestoredRecoveries(browserRecoveries);
          throw new EvidenceReservationNeedsReviewError(
            "An earlier evidence upload requires recovery review. " +
              "Do not upload another file."
          );
        }

        await uploadCaseEvidence({
          caseId,
          lockToken,
          commentId,
          file,
        });
        setEvidenceFiles((pending) => pending.filter((item) => item !== file));
        onEvidenceUploaded();
      }

      setSavedCommentId(null);
      setUploadNeedsReview(false);
      setUncertainUpload(null);
      setEvidenceFiles([]);
      setComment("");
      setIsOpen(false);
    } catch (cause) {
      if (cause instanceof EvidenceReservationNeedsReviewError) {
        setUploadNeedsReview(true);
      }

      if (cause instanceof EvidenceUploadNeedsReviewError) {
          try {
            saveEvidenceRecovery({
              caseId,
              reservationId: cause.reservationId,
              fileName: activeEvidenceFile?.name ?? "Unknown file",
            });
          } catch {
            // Keep the upload blocked even if browser storage is unavailable.
          }

        setUploadNeedsReview(true);
        setUncertainUpload({
          reservationId: cause.reservationId,
          fileName: activeEvidenceFile?.name ?? "Unknown file",
            file: activeEvidenceFile as File,
        });
      }
      setError(
        cause instanceof EvidenceReservationNeedsReviewError
          ? cause.message + " Saving is blocked until reservation recovery is verified."
          : cause instanceof Error
            ? cause.message
            : "Unable to save this activity. Please try again."
      );
    } finally {
      onEvidenceUploadActiveChange(false);
      savingRef.current = false;
      setSaving(false);
    }
  }

  return (
    <div className="contents">
      {!isOpen ? (
        <button
          type="button"
          onClick={() => void openEditorWithRecovery()}
          className="w-fit justify-self-end rounded-md bg-[#51483F] px-4 py-2 text-sm font-medium text-white hover:bg-[#39352F]"
        >
          {evidenceOnlyMode ? "Attach Evidence" : "+ Add Activity"}
        </button>
      ) : (
        <div className="col-span-full w-full rounded-lg border border-[#D8CBB8] bg-white p-6">
          {!evidenceOnlyMode && (
            <>
          <label
            htmlFor="activity-comment"
            className="block text-sm font-semibold text-[#39352F]"
          >
            Work update / Handover comment
          </label>

          <textarea
            id="activity-comment"
            value={comment}
            onChange={(event) => setComment(event.target.value)}
            disabled={saving || savedCommentId !== null}
            maxLength={10000}
            rows={6}
            placeholder="Describe the work completed, information reviewed, or instructions for the next employee..."
            className="mt-3 w-full rounded-md border border-[#C9BBA7] p-4 text-sm leading-6 text-[#39352F] outline-none focus:border-[#51483F] disabled:opacity-60"
          />
            </>
          )}


          <div className="mt-4">
            <label
              htmlFor="activity-evidence"
              className="block text-sm font-semibold text-[#39352F]"
            >
              Supporting evidence
            </label>
            <input
              id="activity-evidence"
              type="file"
              multiple
              accept=".pdf,.jpg,.jpeg,.png,application/pdf,image/jpeg,image/png"
              disabled={saving || (savedCommentId !== null && !evidenceOnlyMode)}
              onChange={(event) => {
                const selected = Array.from(event.target.files ?? []);
                const allowedTypes = new Set([
                  "application/pdf",
                  "image/jpeg",
                  "image/png",
                ]);

                const invalid = selected.some((file) =>
                  !allowedTypes.has(file.type) ||
                  file.size === 0 ||
                  file.size > 10 * 1024 * 1024 ||
                  file.name.length > 255 ||
                  file.name.includes("/") ||
                  file.name.includes(String.fromCharCode(92)) ||
                  Array.from(file.name).some(
                    (character) =>
                      character.charCodeAt(0) < 32 ||
                      character.charCodeAt(0) === 127
                  )
                );

                if (invalid) {
                  setError(
                    "Select PDF, JPG or PNG files up to 10 MiB each, with valid file names. Previously selected files are preserved."
                  );
                  event.target.value = "";
                  return;
                }

                setEvidenceFiles((current) => {
                  const combined = [...current];

                  for (const file of selected) {
                    const alreadySelected = combined.some(
                      (existing) =>
                        existing.name === file.name &&
                        existing.size === file.size &&
                        existing.lastModified === file.lastModified
                    );

                    if (!alreadySelected) {
                      combined.push(file);
                    }
                  }

                  return combined;
                });

                event.target.value = "";
                setError(null);
              }}
              className="mt-2 block w-full rounded-md border border-[#C9BBA7] p-3 text-sm text-[#39352F] disabled:opacity-60"
            />
            <p className="mt-2 text-xs text-[#756B60]">
              PDF, JPG or PNG. Maximum 10 MiB per file.
            </p>
            {evidenceFiles.length > 0 && (
              <div className="mt-3 space-y-2">
                <p className="text-xs font-medium text-[#51483F]">
                  {evidenceFiles.length} file(s) selected
                </p>
                <ul className="space-y-2" aria-label="Selected evidence files">
                  {evidenceFiles.map((file, index) => (
                    <li
                      key={`${file.name}-${file.size}-${file.lastModified}-${index}`}
                      className="flex items-center justify-between gap-3 rounded-md border border-[#E3D9CB] bg-[#FAF8F4] px-3 py-2"
                    >
                      <span className="min-w-0 truncate text-sm text-[#39352F]">
                        {file.name}
                      </span>
                      <div className="flex shrink-0 items-center gap-3">
                        <span className="text-xs text-[#756B60]">
                          {(file.size / 1024 / 1024).toFixed(2)} MB
                        </span>
                        <button
                          type="button"
                          aria-label={`Remove ${file.name}`}
                          title={`Remove ${file.name}`}
                          disabled={saving || uploadNeedsReview || uncertainUpload !== null}
                          onClick={() => {
                            setEvidenceFiles((current) =>
                              current.filter((_, fileIndex) => fileIndex !== index)
                            );
                          }}
                          className="rounded p-1 text-[#756B60] hover:bg-[#EDE5DA] hover:text-red-700 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#51483F] disabled:cursor-not-allowed disabled:opacity-40"
                        >
                          <span aria-hidden="true">×</span>
                        </button>
                      </div>
                    </li>
                  ))}
                </ul>
                <p className="text-xs text-[#756B60]">
                  {evidenceOnlyMode
                    ? "Files will be attached to this existing activity."
                    : "Files will be uploaded when you save this activity."}
                </p>
              </div>
            )}
          </div>

          <p className="mt-3 text-xs text-[#756B60]">
            {!evidenceOnlyMode && ("Internal employee comments are saved to the case activity record. ")}
            Evidence is stored privately and linked to this activity.
          </p>

          {error && (
            <p role="alert" className="mt-4 text-sm text-red-700">
              {error}
            </p>
          )}

          {discoveringRecoveries && (
            <p role="status" className="mt-3 text-sm text-amber-800">
              Checking previous evidence uploads before enabling Save...
            </p>
          )}

          {uploadNeedsReview && !discoveringRecoveries && (
            <button
              type="button"
              onClick={() => void retryRecoveryCheck()}
              disabled={saving || checkingUpload || discoveringRecoveries}
              className="mt-3 rounded-md border border-amber-600 px-3 py-2 text-sm font-medium text-amber-900 disabled:opacity-50"
            >
              Retry Recovery Check
            </button>
          )}

          {databaseRecoveries.length > 0 && (
            <div className="mt-3 rounded-md border border-amber-300 p-3">
              <p className="text-sm font-medium text-amber-900">
                Database records requiring evidence review
              </p>
              {databaseRecoveries.map((record) => (
                <p
                  key={record.reservation_id}
                  className="mt-2 text-sm text-amber-900"
                >
                  {record.file_name} — {record.reservation_status}
                  <span className="block break-all text-xs">
                    Reservation: {record.reservation_id}
                  </span>
                  <button
                    type="button"
                    onClick={() =>
                      void checkDatabaseUploadStatus(record.reservation_id)
                    }
                    disabled={saving || checkingUpload || discoveringRecoveries}
                    className="mt-2 rounded-md border border-amber-600 px-2 py-1 text-xs text-amber-900 disabled:opacity-50"
                  >
                    {checkingUpload ? "Checking..." : "Check Status"}
                  </button>
                </p>
              ))}
              <p className="mt-2 text-xs text-amber-800">
                Do not re-upload these files until their reservation status
                and Storage contents have been reviewed.
              </p>
            </div>
          )}

          {restoredRecoveries.length > 0 && (
            <div className="mt-3 rounded-md border border-amber-300 p-3">
              <p className="text-sm font-medium text-amber-900">
                Previous evidence uploads require review.
              </p>
              {restoredRecoveries.map((record) => (
                <p key={record.reservationId} className="mt-1 text-sm text-amber-900">
                  {record.fileName} — reservation {record.reservationId}
                    <button
                      type="button"
                      onClick={() => void checkRestoredUploadStatus(record.reservationId)}
                      disabled={saving || checkingUpload || discoveringRecoveries}
                      className="ml-3 rounded-md border border-amber-600 px-2 py-1 text-xs text-amber-900 disabled:opacity-50"
                    >
                      {checkingUpload ? "Checking..." : "Check Status"}
                    </button>
                </p>
              ))}
              <p className="mt-2 text-xs text-amber-800">
                Do not re-upload these files until their reservation status
                and Storage contents have been reviewed.
              </p>
            </div>
          )}

          {uncertainUpload && (
            <div className="mt-3 rounded-md border border-amber-300 p-3">
              <p className="text-sm text-amber-900">
                Evidence requiring review: {uncertainUpload.fileName}
              </p>
              <button
                type="button"
                onClick={() => void checkUploadStatus()}
                disabled={saving || checkingUpload || discoveringRecoveries}
                className="mt-2 rounded-md border border-amber-600 px-3 py-2 text-sm text-amber-900 disabled:opacity-50"
              >
                {checkingUpload ? "Checking..." : "Check Upload Status"}
              </button>
            </div>
          )}
          {savedCommentId && (
            <p role="status" className="mt-3 text-sm text-amber-800">
              Your activity comment has already been saved.
              {evidenceFiles.length > 0
                ? " Some evidence files are still pending."
                : ""}
              {uploadNeedsReview
                ? " An uncertain upload requires review before retrying."
                : ""}
            </p>
          )}

          <div className="mt-5 flex justify-end gap-3">
            <button
              type="button"
              onClick={closeEditor}
              disabled={saving}
              className="rounded-md border border-[#C9BBA7] px-4 py-2 text-sm text-[#39352F] hover:bg-[#F4F0E9] disabled:opacity-50"
            >
              {savedCommentId ? "Close" : "Cancel"}
            </button>
            <button
              type="button"
              onClick={() => void saveActivity()}
              disabled={
            saving ||
            uploadNeedsReview ||
            (evidenceOnlyMode
                ? evidenceFiles.length === 0
                : !savedCommentId && !comment.trim() && evidenceFiles.length === 0)
          }
              className="rounded-md bg-[#51483F] px-4 py-2 text-sm font-medium text-white hover:bg-[#39352F] disabled:opacity-50"
            >
              {saving
                  ? "Saving..."
                  : uploadNeedsReview
                    ? "Upload Requires Review"
                    : evidenceOnlyMode
                      ? "Attach Evidence"
                      : savedCommentId
                        ? "Retry Pending Evidence"
                        : "Save Activity"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
