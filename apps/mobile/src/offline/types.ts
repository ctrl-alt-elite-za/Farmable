export type SyncState = 'pending' | 'syncing' | 'synced' | 'failed' | 'conflict';
export interface Scope {
  ownerId: string;
  farmId: string;
}
export interface ObservationInput {
  id: string;
  sectionId: string;
  type: string;
  note: string;
  healthStatus?: string | null;
  actionTaken?: string | null;
  createdByVoice?: boolean;
}
export interface Observation extends ObservationInput, Scope {
  createdAt: number;
  updatedAt: number;
  version: number;
  localMediaId: string | null;
  syncState: SyncState;
}
export interface Media extends Scope {
  id: string;
  relativePath: string;
  contentType: 'image/jpeg' | 'image/png';
  byteLength: number;
  cloudId: string | null;
}
export interface Mutation {
  mutation_id: string;
  owner_id: string;
  farm_id: string;
  entity_type: 'observation' | 'media';
  entity_id: string;
  operation: 'create' | 'upload';
  payload: string;
  created_at: number;
  attempt_count: number;
  budget_count: number;
  sync_state: SyncState;
  next_attempt_at: number;
  dependency_id: string | null;
  error_code: string | null;
}
export type FailureKind = 'transient' | 'validation' | 'conflict' | 'auth' | 'missing_media';
export class OfflineError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = 'OfflineError';
  }
}
export class TransportError extends Error {
  constructor(public readonly kind: FailureKind) {
    super(kind);
    this.name = 'TransportError';
  }
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
export function uuid(value: string): string {
  if (typeof value !== 'string' || !UUID.test(value)) throw new OfflineError('invalid_uuid');
  return value;
}
export function scope(value: Scope): Scope {
  return { ownerId: uuid(value.ownerId), farmId: uuid(value.farmId) };
}
function bounded(value: unknown, max: number, required = false): string | null {
  if (value === undefined || value === null) {
    if (required) throw new OfflineError('invalid_observation');
    return null;
  }
  if (typeof value !== 'string' || value.length > max || (required && !value.trim()))
    throw new OfflineError('invalid_observation');
  return value;
}
export function normalizeObservation(input: ObservationInput): ObservationInput {
  if (input.createdByVoice !== undefined && typeof input.createdByVoice !== 'boolean')
    throw new OfflineError('invalid_observation');
  return {
    id: uuid(input.id),
    sectionId: uuid(input.sectionId),
    type: bounded(input.type, 100, true)!,
    note: bounded(input.note, 10000, true)!,
    healthStatus: bounded(input.healthStatus, 100),
    actionTaken: bounded(input.actionTaken, 10000),
    createdByVoice: input.createdByVoice ?? false,
  };
}
export function payload(value: unknown): string {
  const result = JSON.stringify(value);
  // encodeURIComponent measures UTF-8 without depending on a native TextEncoder.
  let length: number;
  try {
    length = encodeURIComponent(result).replace(/%[A-F\d]{2}/g, 'x').length;
  } catch {
    throw new OfflineError('invalid_payload');
  }
  if (length > 65536) throw new OfflineError('payload_too_large');
  return result;
}
export function timestamp(value: number): number {
  if (!Number.isSafeInteger(value) || value < 0) throw new OfflineError('invalid_time');
  return value;
}
