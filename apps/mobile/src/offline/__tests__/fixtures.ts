import type { Attachment } from '../store';
export const ownerId = '11111111-1111-4111-8111-111111111111';
export const farmId = '22222222-2222-4222-8222-222222222222';
export const observation = {
  id: '33333333-3333-4333-8333-333333333333',
  sectionId: '44444444-4444-4444-8444-444444444444',
  type: 'note',
  note: 'Saved offline',
};
export const mutationId = '55555555-5555-4555-8555-555555555555';
export const mediaId = '66666666-6666-4666-8666-666666666666';
export const uploadId = '77777777-7777-4777-8777-777777777777';
export const otherId = '88888888-8888-4888-8888-888888888888';
export const cloudId = '99999999-9999-4999-8999-999999999999';
export const attachment: Attachment = {
  mutationId: uploadId,
  media: {
    id: mediaId,
    ownerId,
    farmId,
    relativePath: `${ownerId}/${farmId}/${mediaId}.png`,
    contentType: 'image/png',
    byteLength: 68,
    cloudId: null,
  },
};
