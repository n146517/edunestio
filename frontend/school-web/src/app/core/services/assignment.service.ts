import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';
import { environment } from '../../../environments/environment';
import {
  ApiResponse,
  Assignment,
  AssignmentSubmission,
  AssignmentUpsert,
  ItemsData,
  StudentAssignment
} from '../models/api.models';

/** Typed client for the Assignments module. */
@Injectable({ providedIn: 'root' })
export class AssignmentService {
  private readonly http = inject(HttpClient);
  private readonly base = `${environment.apiBaseUrl}/assignments`;

  /** Staff list with optional class/section/subject filters. */
  list(q: { classId?: number; sectionId?: number; subjectId?: number } = {}): Observable<Assignment[]> {
    let p = new HttpParams();
    if (q.classId) p = p.set('classId', q.classId);
    if (q.sectionId) p = p.set('sectionId', q.sectionId);
    if (q.subjectId) p = p.set('subjectId', q.subjectId);
    return this.http
      .get<ApiResponse<ItemsData<Assignment>>>(this.base, { params: p })
      .pipe(map((r) => r.data?.items ?? []));
  }

  /** The signed-in student's assignments (with their own submission state). */
  mine(): Observable<StudentAssignment[]> {
    return this.http
      .get<ApiResponse<ItemsData<StudentAssignment>>>(`${this.base}/mine`)
      .pipe(map((r) => r.data?.items ?? []));
  }

  /** All students' submissions for an assignment (teacher review). */
  submissions(assignmentId: number): Observable<AssignmentSubmission[]> {
    return this.http
      .get<ApiResponse<ItemsData<AssignmentSubmission>>>(`${this.base}/${assignmentId}/submissions`)
      .pipe(map((r) => r.data?.items ?? []));
  }

  save(body: AssignmentUpsert): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(this.base, body);
  }

  submit(assignmentId: number, content: string): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/submit`, { AssignmentId: assignmentId, Content: content });
  }

  grade(submissionId: number, marks: number | null, feedback: string | null): Observable<ApiResponse> {
    return this.http.post<ApiResponse>(`${this.base}/grade`, { SubmissionId: submissionId, Marks: marks, Feedback: feedback });
  }

  delete(assignmentId: number): Observable<ApiResponse> {
    return this.http.delete<ApiResponse>(`${this.base}/${assignmentId}`);
  }
}
