export const appleWatchAdapter = {
  type: 'apple-watch',
  displayName: 'Apple Watch',
  previewLimit: 4000,

  shapeRequest(request) {
    return {
      id: request.id,
      title: request.title,
      summary: request.summary,
      preview: request.preview.slice(0, this.previewLimit),
      source: request.source,
      status: request.status,
      createdAt: request.createdAt,
      expiresAt: request.expiresAt
    };
  }
};
