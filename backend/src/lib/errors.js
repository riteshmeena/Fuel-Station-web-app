export class HttpError extends Error {
  constructor(status, message, code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

export const badRequest = (msg, code = 'BAD_REQUEST') => new HttpError(400, msg, code);
export const unauthorized = (msg = 'Please log in', code = 'UNAUTHORIZED') => new HttpError(401, msg, code);
export const forbidden = (msg = 'Not allowed', code = 'FORBIDDEN') => new HttpError(403, msg, code);
export const notFound = (msg = 'Not found') => new HttpError(404, msg, 'NOT_FOUND');
export const conflict = (msg, code = 'CONFLICT') => new HttpError(409, msg, code);

// Wraps async route handlers so thrown errors reach the error middleware.
export const ah = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);
