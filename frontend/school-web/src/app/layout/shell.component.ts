import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { RouterLink, RouterLinkActive, RouterOutlet } from '@angular/router';
import { AuthStore } from '../core/auth/auth.store';
import { AuthService } from '../core/auth/auth.service';
import { AcademicYearStore } from '../core/state/academic-year.store';
import { Router } from '@angular/router';

interface NavItem {
  label: string;
  route: string[];
  /** Emoji/icon shown for a top-level group header. */
  icon?: string;
  /** When true, the item is a planned (not yet implemented) module. */
  planned?: boolean;
  /** Permission required to see this item (any one of them). Omit = always visible. */
  perm?: string | string[];
  /** Optional child items shown as a collapsible sub-menu. */
  children?: NavItem[];
}

@Component({
  selector: 'app-shell',
  imports: [RouterOutlet, RouterLink, RouterLinkActive, FormsModule],
  templateUrl: './shell.component.html',
  styleUrl: './shell.component.scss'
})
export class ShellComponent {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);
  protected readonly store = inject(AuthStore);
  protected readonly yearStore = inject(AcademicYearStore);

  /** Staff see the global academic-year switcher; students/guardians do not. */
  protected readonly showYearPicker = !this.store.isStudentOrGuardian();

  constructor() {
    if (this.showYearPicker) this.yearStore.load();
  }

  /** Handle the header year dropdown change. */
  protected onYearChange(id: number): void {
    this.yearStore.select(Number(id));
  }

  protected readonly menuOpen = signal(false);
  /** Mobile sidebar drawer open state. */
  protected readonly navOpen = signal(false);

  protected toggleNav(): void { this.navOpen.update((v) => !v); }
  protected closeNav(): void { this.navOpen.set(false); }

  /** Groups are expanded by default (collapsible by the user). */
  protected readonly expanded = signal<Set<string>>(new Set<string>());

  /** Groups are open unless the user has explicitly collapsed them. */
  protected isExpanded(label: string): boolean {
    return !this.expanded().has(label); // set holds the COLLAPSED labels
  }

  protected toggleGroup(label: string): void {
    const next = new Set(this.expanded());
    if (next.has(label)) next.delete(label); else next.add(label);
    this.expanded.set(next);
  }

  /**
   * Navigation. Each item declares the permission(s) that reveal it, so the sidebar
   * only shows what the signed-in user can actually open. This matches the route
   * guards in app.routes.ts (a Teacher, for example, only sees Marks Entry +
   * Report Cards under the Exams group).
   */
  private readonly allNav: NavItem[] = [
    { label: 'Dashboard', route: ['/dashboard'], icon: '🏠' },

    {
      label: 'Student Management', route: ['/students'], icon: '👨‍🎓',
      children: [
        { label: 'Students', route: ['/students'], perm: 'student.view' },
        { label: 'Admissions', route: ['/admissions'], perm: 'admission.view' },
        { label: 'Attendance', route: ['/attendance'], perm: 'attendance.view' },
        { label: 'Leave Requests', route: ['/leave/requests'], perm: 'leave.manage' }
      ]
    },

    {
      label: 'Academic Management', route: ['/academic-setup'], icon: '📚',
      children: [
        { label: 'Academic Setup', route: ['/academic-setup'], perm: 'academic.view' },
        { label: 'Timetable', route: ['/timetable'], perm: 'timetable.manage' },
        { label: 'Assignments', route: ['/assignments'], perm: 'assignment.manage' },
        { label: 'Library', route: ['/placeholder', 'library'], planned: true }
      ]
    },

    {
      label: 'Examination', route: ['/exams'], icon: '📝',
      perm: ['exam.view', 'exam.marks', 'exam.reportcard'],
      children: [
        { label: 'Examination', route: ['/exams'], perm: 'exam.view' },
        { label: 'Marks Entry', route: ['/exams/marks'], perm: 'exam.marks' },
        { label: 'Results', route: ['/exams/results'], perm: 'exam.view' },
        { label: 'Report Cards', route: ['/exams/report-cards'], perm: 'exam.reportcard' }
      ]
    },

    {
      label: 'Fees & Finance', route: ['/fees'], icon: '💳', perm: 'fee.view',
      children: [
        { label: 'Fees & Finance', route: ['/fees'], perm: 'fee.view' }
      ]
    },

    {
      label: 'Administration', route: ['/placeholder', 'staff-hr'], icon: '🧑‍💼',
      children: [
        { label: 'Staff & HR', route: ['/placeholder', 'staff-hr'], planned: true },
        { label: 'Transport', route: ['/placeholder', 'transport'], planned: true },
        { label: 'Communication', route: ['/placeholder', 'communication'], planned: true }
      ]
    },

    {
      label: 'Settings', route: ['/settings'], icon: '⚙️', perm: 'settings.view',
      children: [
        { label: 'General Settings', route: ['/settings'], perm: 'settings.view' },
        { label: 'Academic Year', route: ['/academic-setup'], perm: 'academic.view' },
        { label: 'Classes & Sections', route: ['/academic-setup'], perm: 'academic.view' }
      ]
    }
  ];

  /** True when the user has access to a nav item (no perm declared = visible). */
  private canSee(item: NavItem): boolean {
    if (!item.perm) return true;
    const perms = Array.isArray(item.perm) ? item.perm : [item.perm];
    return perms.some((p) => this.store.hasPermission(p));
  }

  /**
   * The nav for the current user. Self-service students/guardians get a dedicated
   * minimal menu (own profile + leave); everyone else gets the permission-filtered
   * staff navigation with empty groups hidden.
   */
  protected readonly nav: NavItem[] = this.buildNav();

  private buildNav(): NavItem[] {
    const sid = this.store.studentId();
    if (this.store.isStudentOrGuardian() && sid) {
      // Self-service: a flat, minimal menu.
      return [
        { label: 'My Profile', route: ['/students', String(sid)], icon: '👤' },
        { label: 'My Timetable', route: ['/my-timetable'], icon: '🗓' },
        { label: 'My Assignments', route: ['/my-assignments'], icon: '📒' },
        { label: 'My Attendance', route: ['/my-attendance'], icon: '✅' },
        { label: 'Apply Leave', route: ['/leave/apply'], icon: '📝' },
        { label: 'My Leaves', route: ['/leave/mine'], icon: '📋' }
      ];
    }
    return this.allNav
      .map((item) => item.children
        ? { ...item, children: item.children.filter((c) => this.canSee(c)) }
        : item)
      // Keep a group only if it has at least one visible child; keep plain items the user can see.
      .filter((item) => item.children ? item.children.length > 0 : this.canSee(item));
  }

  protected toggleMenu(): void {
    this.menuOpen.update((v) => !v);
  }

  protected logout(): void {
    this.auth.logout();
    void this.router.navigate(['/login']);
  }
}
