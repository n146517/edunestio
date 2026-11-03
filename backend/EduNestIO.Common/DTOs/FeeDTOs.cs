namespace EduNestIO.Common.DTOs;

public class FeeHeadVO
{
    public long? FeeHeadId { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;
    public bool IsActive { get; set; } = true;
}

public class FeeStructureVO
{
    public long? FeeStructureId { get; set; }
    public long FeeHeadId { get; set; }
    public long? ClassId { get; set; }
    public decimal Amount { get; set; }
    public string Period { get; set; } = "Annual";
}

public class FeeAssignVO
{
    public long StudentId { get; set; }
    public long FeeHeadId { get; set; }
    public decimal Amount { get; set; }
    public decimal Discount { get; set; }
    public DateTime? DueDate { get; set; }
    public string? Note { get; set; }
}

public class PaymentAllocationVO
{
    public long FeeAssignmentId { get; set; }
    public decimal Amount { get; set; }
}

public class PaymentVO
{
    public long StudentId { get; set; }
    public decimal Amount { get; set; }
    public string Mode { get; set; } = "Cash";
    public string? Reference { get; set; }
    public List<PaymentAllocationVO>? Allocations { get; set; }
}

public class PaymentReverseVO
{
    public long PaymentId { get; set; }
    public string? Reason { get; set; }
}
