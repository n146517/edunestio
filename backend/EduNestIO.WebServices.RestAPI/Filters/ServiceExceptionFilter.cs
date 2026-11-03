using EduNestIO.Common;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Logging;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace EduNestIO.WebServices.RestAPI.Filters;

/// <summary>
/// Centralized exception handling: converts unhandled exceptions into a consistent
/// ApiResponse with INTERNAL_SERVER_ERROR and a correlation id. Full detail is
/// logged server-side only; the client body never leaks stack traces.
/// Usable both as a global filter and as a [ServiceExceptionFilter] attribute.
/// </summary>
[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
public sealed class ServiceExceptionFilter : Attribute, IExceptionFilter
{
    public void OnException(ExceptionContext context)
    {
        var correlationId = context.HttpContext.Items.TryGetValue("CorrelationId", out var cid)
            ? cid?.ToString() : null;

        LogWriter.WriteLog(new LogDTO
        {
            FunctionName = context.ActionDescriptor.DisplayName,
            ClassName = nameof(ServiceExceptionFilter),
            LogStringLevel = LoggingLevel.Exceptional,
            ExceptionString = context.Exception.Message,
            StackTrace = context.Exception.StackTrace,
            CorrelationId = correlationId,
            Message = "Unhandled exception"
        });

        context.Result = new ObjectResult(
            ApiResponse.Fail(ResultCodes.INTERNAL_SERVER_ERROR,
                "An unexpected error occurred. Please quote the correlation id.", correlationId))
        {
            StatusCode = StatusCodes.Status500InternalServerError
        };
        context.ExceptionHandled = true;
    }
}
