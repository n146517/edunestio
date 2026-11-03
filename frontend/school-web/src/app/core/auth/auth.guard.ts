import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthStore } from './auth.store';

/**
 * Route guard that redirects unauthenticated users to the login page. This is a
 * UX convenience; the API independently rejects unauthorized requests.
 */
export const authGuard: CanActivateFn = (_route, state) => {
  const store = inject(AuthStore);
  const router = inject(Router);

  if (store.isAuthenticated()) {
    return true;
  }

  return router.createUrlTree(['/login'], { queryParams: { returnUrl: state.url } });
};

/**
 * Guard factory requiring a specific permission. Mirrors (but does not replace)
 * the server-side permission policy.
 */
export function permissionGuard(permission: string): CanActivateFn {
  return () => {
    const store = inject(AuthStore);
    const router = inject(Router);

    if (!store.isAuthenticated()) {
      return router.createUrlTree(['/login']);
    }
    return store.hasPermission(permission) ? true : router.createUrlTree(['/forbidden']);
  };
}

/**
 * Landing guard for the index route. Self-service students/guardians are sent
 * straight to their own profile; everyone else goes to the dashboard.
 */
export const homeRedirectGuard: CanActivateFn = () => {
  const store = inject(AuthStore);
  const router = inject(Router);
  const sid = store.studentId();
  if (store.isStudentOrGuardian() && sid) {
    return router.createUrlTree(['/students', sid]);
  }
  return router.createUrlTree(['/dashboard']);
};

/**
 * Guard for the staff Dashboard. Self-service students/guardians don't have a
 * dashboard — they are redirected to their own profile.
 */
export const dashboardGuard: CanActivateFn = () => {
  const store = inject(AuthStore);
  const router = inject(Router);
  if (!store.isAuthenticated()) {
    return router.createUrlTree(['/login']);
  }
  const sid = store.studentId();
  if (store.isStudentOrGuardian() && sid) {
    return router.createUrlTree(['/students', sid]);
  }
  return true;
};

/**
 * Guard for the admin student LIST. A self-service student/guardian must never see
 * the full roster — they are redirected to their own profile instead.
 */
export const studentListGuard: CanActivateFn = () => {
  const store = inject(AuthStore);
  const router = inject(Router);
  if (!store.isAuthenticated()) {
    return router.createUrlTree(['/login']);
  }
  const sid = store.studentId();
  if (store.isStudentOrGuardian()) {
    return sid ? router.createUrlTree(['/students', sid]) : router.createUrlTree(['/forbidden']);
  }
  return store.hasPermission('student.view') ? true : router.createUrlTree(['/forbidden']);
};
