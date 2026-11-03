import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthStore } from '../auth/auth.store';
import { environment } from '../../../environments/environment';

/**
 * Attaches the bearer token to EduNestIO API requests only. Requests to other
 * origins are left untouched so the token never leaks to third parties.
 */
export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const store = inject(AuthStore);
  const token = store.token;
  const isApiCall = req.url.startsWith(environment.apiBaseUrl);

  if (token && isApiCall) {
    req = req.clone({ setHeaders: { Authorization: `Bearer ${token}` } });
  }
  return next(req);
};
