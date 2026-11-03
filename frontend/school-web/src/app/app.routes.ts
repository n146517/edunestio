import { Routes } from '@angular/router';
import { authGuard, permissionGuard, homeRedirectGuard, studentListGuard, dashboardGuard } from './core/auth/auth.guard';

/**
 * Application routes. Authenticated pages live under the shell layout. Placeholder
 * routes for planned modules are present so navigation is complete, but they render
 * a "coming soon" page rather than pretending business functionality exists.
 */
export const routes: Routes = [
  {
    path: 'login',
    loadComponent: () => import('./features/auth/login.component').then((m) => m.LoginComponent)
  },
  {
    path: 'forbidden',
    loadComponent: () => import('./features/errors/forbidden.component').then((m) => m.ForbiddenComponent)
  },
  {
    path: '',
    loadComponent: () => import('./layout/shell.component').then((m) => m.ShellComponent),
    canActivate: [authGuard],
    children: [
      { path: '', pathMatch: 'full', canActivate: [homeRedirectGuard], children: [] },
      {
        path: 'dashboard',
        canActivate: [dashboardGuard],
        loadComponent: () => import('./features/dashboard/dashboard.component').then((m) => m.DashboardComponent)
      },
      {
        path: 'students',
        canActivate: [studentListGuard],
        loadComponent: () =>
          import('./features/students/students.component').then((m) => m.StudentsComponent)
      },
      {
        path: 'students/new',
        canActivate: [permissionGuard('student.create')],
        loadComponent: () =>
          import('./features/students/student-form.component').then((m) => m.StudentFormComponent)
      },
      {
        path: 'students/:id/edit',
        canActivate: [permissionGuard('student.update')],
        loadComponent: () =>
          import('./features/students/student-form.component').then((m) => m.StudentFormComponent)
      },
      {
        path: 'students/:id',
        canActivate: [permissionGuard('student.view')],
        loadComponent: () =>
          import('./features/students/student-detail.component').then((m) => m.StudentDetailComponent)
      },
      {
        path: 'academic-setup',
        canActivate: [permissionGuard('academic.view')],
        loadComponent: () =>
          import('./features/academic/academic-setup.component').then((m) => m.AcademicSetupComponent)
      },
      {
        path: 'admissions',
        canActivate: [permissionGuard('admission.view')],
        loadComponent: () =>
          import('./features/admissions/admissions.component').then((m) => m.AdmissionsComponent)
      },
      {
        path: 'attendance',
        canActivate: [permissionGuard('attendance.view')],
        loadComponent: () =>
          import('./features/attendance/attendance.component').then((m) => m.AttendanceComponent)
      },
      {
        path: 'my-attendance',
        canActivate: [permissionGuard('attendance.view')],
        loadComponent: () =>
          import('./features/attendance/my-attendance.component').then((m) => m.MyAttendanceComponent)
      },
      {
        path: 'fees',
        canActivate: [permissionGuard('fee.view')],
        loadComponent: () =>
          import('./features/fees/fees.component').then((m) => m.FeesComponent)
      },
      {
        path: 'exams',
        canActivate: [permissionGuard('exam.view')],
        loadComponent: () =>
          import('./features/exams/exams.component').then((m) => m.ExamsComponent)
      },
      {
        path: 'exams/new',
        canActivate: [permissionGuard('exam.manage')],
        loadComponent: () =>
          import('./features/exams/exam-wizard.component').then((m) => m.ExamWizardComponent)
      },
      {
        path: 'exams/marks',
        canActivate: [permissionGuard('exam.marks')],
        loadComponent: () =>
          import('./features/exams/marks-entry.component').then((m) => m.MarksEntryComponent)
      },
      {
        path: 'exams/results',
        canActivate: [permissionGuard('exam.view')],
        loadComponent: () =>
          import('./features/exams/results.component').then((m) => m.ResultsComponent)
      },
      {
        path: 'exams/report-cards',
        canActivate: [permissionGuard('exam.reportcard')],
        loadComponent: () =>
          import('./features/exams/report-cards.component').then((m) => m.ReportCardsComponent)
      },
      {
        path: 'exams/:examId/report-card/:studentId',
        canActivate: [permissionGuard('exam.reportcard')],
        loadComponent: () =>
          import('./features/exams/report-card-view.component').then((m) => m.ReportCardViewComponent)
      },
      {
        path: 'exams/:id/edit',
        canActivate: [permissionGuard('exam.manage')],
        loadComponent: () =>
          import('./features/exams/exam-wizard.component').then((m) => m.ExamWizardComponent)
      },
      {
        path: 'exams/:id',
        canActivate: [permissionGuard('exam.view')],
        loadComponent: () =>
          import('./features/exams/exam-wizard.component').then((m) => m.ExamWizardComponent)
      },
      // ---- Leave management ----
      {
        path: 'leave/apply',
        canActivate: [permissionGuard('leave.apply')],
        loadComponent: () =>
          import('./features/leave/leave-apply.component').then((m) => m.LeaveApplyComponent)
      },
      {
        path: 'leave/mine',
        canActivate: [permissionGuard('leave.apply')],
        loadComponent: () =>
          import('./features/leave/my-leaves.component').then((m) => m.MyLeavesComponent)
      },
      {
        path: 'leave/requests',
        canActivate: [permissionGuard('leave.manage')],
        loadComponent: () =>
          import('./features/leave/leave-admin.component').then((m) => m.LeaveAdminComponent)
      },
      {
        path: 'settings',
        canActivate: [permissionGuard('settings.view')],
        loadComponent: () =>
          import('./features/settings/settings.component').then((m) => m.SettingsComponent)
      },
      // ---- Timetable ----
      {
        path: 'timetable',
        canActivate: [permissionGuard('timetable.manage')],
        loadComponent: () =>
          import('./features/timetable/timetable.component').then((m) => m.TimetableComponent)
      },
      {
        path: 'my-timetable',
        canActivate: [permissionGuard('timetable.view')],
        loadComponent: () =>
          import('./features/timetable/my-timetable.component').then((m) => m.MyTimetableComponent)
      },
      // ---- Assignments ----
      {
        path: 'assignments',
        canActivate: [permissionGuard('assignment.manage')],
        loadComponent: () =>
          import('./features/assignments/assignments.component').then((m) => m.AssignmentsComponent)
      },
      {
        path: 'my-assignments',
        canActivate: [permissionGuard('assignment.submit')],
        loadComponent: () =>
          import('./features/assignments/my-assignments.component').then((m) => m.MyAssignmentsComponent)
      },
      // Placeholder routes for planned modules (see docs/implementation-status.md).
      {
        path: 'placeholder/:module',
        loadComponent: () => import('./features/placeholder/placeholder.component').then((m) => m.PlaceholderComponent)
      }
    ]
  },
  { path: '**', redirectTo: '' }
];
