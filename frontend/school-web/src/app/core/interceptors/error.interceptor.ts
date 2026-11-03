import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { Router } from '@angular/router';
import { catchError, throwError } from 'rxjs';
import { AuthStore } from '../auth/auth.store';
import { NotificationService } from '../services/notification.service';
import { ApiResponse } from '../models/api.models';

/**
 * Centralized API error handling. Translates HTTP failures into user-facing
 * messages, handles 401/403 uniformly, and surfaces the correlation id for support.
 */
export const errorInterceptor: HttpInterceptorFn = (req, next) => {
  const router = inject(Router);
  const store = inject(AuthStore);
  const notifications = inject(NotificationService);

  return next(req).pipe(
    catchError((error: HttpErrorResponse) => {
      const body = error.error as ApiResponse | null;
      const cid = body?.correlationId;
      const desc = body?.resultCodeDescription;

      switch (error.status) {
        case 0:
          notifications.error('Cannot reach the server. Check your connection.');
          break;
        case 401:
          store.clear();
          notifications.error('Your session has expired. Please sign in again.');
          void router.navigate(['/login']);
          break;
        case 403:
          // Surface the denial but DON'T force the whole page to /forbidden — a single
          // secondary call failing (e.g. a dropdown's data) shouldn't blow away the
          // screen. Route-level permission is already enforced by the route guards.
          notifications.error(desc ?? 'You do not have permission to perform this action.');
          break;
        default:
          notifications.error(`${desc ?? 'Something went wrong.'}${cid ? ` (ref: ${cid})` : ''}`);
      }
      return throwError(() => error);
    })
  );
};
