async function parseReceipt(response: Response): Promise<Record<string, unknown> | null> {
  if (!response.ok) return null;
  const body: unknown = await response.json().catch(() => null);
  if (body === null || typeof body !== "object" || Array.isArray(body)) return null;
  return body as Record<string, unknown>;
}

/** An HTTP status alone is not a receipt; an isolated or suppressed signal isn't linked. */
export async function hasSignalReceipt(response: Response, signalKey: string): Promise<boolean> {
  const receipt = await parseReceipt(response);
  return receipt?.accepted === true
    && typeof receipt.duplicate === "boolean"
    && receipt.signal_key === signalKey
    && receipt.processing_status === "linked";
}

export async function hasLinkReceipt(
  response: Response,
  matrixPersonId: string,
  linkStatus: "linked" | "revoked",
): Promise<boolean> {
  const receipt = await parseReceipt(response);
  return receipt?.accepted === true
    && receipt.matrix_person_id === matrixPersonId
    && receipt.link_status === linkStatus
    && receipt.marketing_enabled === false
    && receipt.external_action_enabled === false;
}
