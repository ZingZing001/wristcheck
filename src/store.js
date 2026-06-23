import { randomUUID } from 'node:crypto';

export class ApprovalStore {
  #requests = new Map();

  create(input) {
    const now = new Date();
    const timeoutSeconds = Number(input.timeoutSeconds || 300);
    const request = {
      id: randomUUID(),
      title: String(input.title || 'Copilot step approval'),
      summary: String(input.summary || ''),
      preview: String(input.preview || ''),
      source: String(input.source || 'copilot-cli'),
      status: 'pending',
      createdAt: now.toISOString(),
      expiresAt: new Date(now.getTime() + timeoutSeconds * 1000).toISOString(),
      decidedAt: null,
      decidedBy: null,
      watchType: null
    };

    this.#requests.set(request.id, request);
    return request;
  }

  get(id) {
    const request = this.#requests.get(id);
    if (!request) return null;

    if (request.status === 'pending' && Date.parse(request.expiresAt) <= Date.now()) {
      request.status = 'expired';
    }

    return request;
  }

  nextPending() {
    for (const request of this.#requests.values()) {
      const current = this.get(request.id);
      if (current?.status === 'pending') return current;
    }

    return null;
  }

  list() {
    return Array.from(this.#requests.values())
      .map((request) => this.get(request.id))
      .filter(Boolean)
      .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
  }

  decide(id, decision, details = {}) {
    const request = this.get(id);
    if (!request) return { error: 'not_found' };
    if (request.status !== 'pending') return { error: 'already_decided', request };
    if (!['approved', 'denied'].includes(decision)) return { error: 'invalid_decision' };

    request.status = decision;
    request.decidedAt = new Date().toISOString();
    request.decidedBy = String(details.actor || 'watch');
    request.watchType = String(details.watchType || 'apple-watch');
    return { request };
  }
}
