-- ============================================================================
-- HỆ THỐNG QUẢN LÝ KHÁCH SẠN (HOTEL MANAGEMENT SYSTEM - PMS)
-- KỊCH BẢN T-SQL TƯƠNG THÍCH HOÀN TOÀN VỚI MICROSOFT SQL SERVER
-- BAO GỒM ĐÚNG 20 BẢNG CHUẨN HÓA (3NF) - HỖ TRỢ ĐẦY ĐỦ TIẾNG VIỆT UNICODE (NVARCHAR)
-- ============================================================================

-- 1. Tạo Database mới (nếu chưa có)
IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'HotelPMS_DB')
BEGIN
    CREATE DATABASE HotelPMS_DB COLLATE Vietnamese_CI_AS;
END
GO

USE HotelPMS_DB;
GO

-- 2. Xóa bảng cũ nếu tồn tại (theo thứ tự từ bảng con đến bảng cha)
DROP TABLE IF EXISTS notifications;
DROP TABLE IF EXISTS customer_feedback;
DROP TABLE IF EXISTS purchase_orders;
DROP TABLE IF EXISTS inventory_items;
DROP TABLE IF EXISTS security_incidents;
DROP TABLE IF EXISTS maintenance_tickets;
DROP TABLE IF EXISTS housekeeping_tasks;
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS service_orders;
DROP TABLE IF EXISTS services;
DROP TABLE IF EXISTS room_stays;
DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS guests;
DROP TABLE IF EXISTS rate_plans;
DROP TABLE IF EXISTS rooms;
DROP TABLE IF EXISTS room_types;
DROP TABLE IF EXISTS work_shifts;
DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS roles;
GO

-- ============================================================================
-- PHẦN 1: HỆ THỐNG, PHÂN QUYỀN & NHÂN SỰ (HR & ADMIN)
-- ============================================================================

-- 1. Bảng Vai trò & Phân quyền (UC.15.01)
CREATE TABLE roles (
    role_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    role_name NVARCHAR(50) NOT NULL UNIQUE,       -- ADMIN, MANAGER, RECEPTIONIST, HOUSEKEEPER, ACCOUNTANT...
    description NVARCHAR(255) NULL,
    permissions NVARCHAR(MAX) NULL,              -- Chuỗi JSON cấu hình phân quyền
    created_at DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT chk_roles_permissions CHECK (permissions IS NULL OR ISJSON(permissions) = 1)
);
GO

-- 2. Bảng Nhân viên & Tài khoản hệ thống (UC.11.01, UC.15.01)
CREATE TABLE employees (
    employee_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    role_id BIGINT NOT NULL,
    full_name NVARCHAR(100) NOT NULL,
    username NVARCHAR(50) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    email VARCHAR(100) NULL UNIQUE,
    phone VARCHAR(20) NULL,
    department NVARCHAR(50) NOT NULL,            -- FRONT_OFFICE, HOUSEKEEPING, FNB, MAINTENANCE, ACCOUNTING, HR, SECURITY
    hire_date DATE NULL,
    status NVARCHAR(20) DEFAULT N'ACTIVE',       -- ACTIVE, PROBATION, INACTIVE, TERMINATED
    created_at DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_emp_role FOREIGN KEY (role_id) REFERENCES roles(role_id)
);
GO

-- 3. Bảng Phân ca làm việc & Lịch trực (UC.11.02)
CREATE TABLE work_shifts (
    shift_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    employee_id BIGINT NOT NULL,
    shift_date DATE NOT NULL,
    shift_type NVARCHAR(20) NOT NULL,            -- CA_SANG (06:00-14:00), CA_CHIEU (14:00-22:00), CA_DEM (22:00-06:00)
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    status NVARCHAR(20) DEFAULT N'SCHEDULED',    -- SCHEDULED, COMPLETED, ABSENT, SWAPPED
    notes NVARCHAR(MAX) NULL,
    created_at DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_shift_emp FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);
GO

-- ============================================================================
-- PHẦN 2: QUẢN LÝ PHÒNG & GIÁ DOANH THU (ROOMS & PRICING)
-- ============================================================================

-- 4. Bảng Loại phòng / Hạng phòng (UC.01.01)
CREATE TABLE room_types (
    room_type_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    type_name NVARCHAR(50) NOT NULL UNIQUE,      -- Standard, Superior, Deluxe, Suite, Executive
    base_price DECIMAL(12,2) NOT NULL,          -- Giá niêm yết cơ sở
    max_adults INT NOT NULL DEFAULT 2,
    max_children INT NOT NULL DEFAULT 1,
    size_sqm DECIMAL(6,2) NULL,                 -- Diện tích (m2)
    description NVARCHAR(MAX) NULL,
    created_at DATETIME2 DEFAULT GETDATE()
);
GO

-- 5. Bảng Danh sách phòng & Trạng thái (UC.01.01, UC.01.02, UC.01.03)
CREATE TABLE rooms (
    room_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    room_type_id BIGINT NOT NULL,
    room_number NVARCHAR(20) NOT NULL UNIQUE,   -- Số phòng: 101, 102, 201...
    floor INT NOT NULL,
    status NVARCHAR(30) DEFAULT N'AVAILABLE',   -- AVAILABLE, OCCUPIED, CLEANING, INSPECTION, OUT_OF_ORDER
    key_card_uid VARCHAR(64) NULL,              -- Mã thẻ từ gắn với phòng
    notes NVARCHAR(MAX) NULL,
    updated_at DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_room_type FOREIGN KEY (room_type_id) REFERENCES room_types(room_type_id)
);
GO

-- 6. Bảng Chính sách giá động & Kênh phân phối OTA (UC.02.03, UC.12.01)
CREATE TABLE rate_plans (
    rate_plan_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    room_type_id BIGINT NOT NULL,
    channel_name NVARCHAR(50) NOT NULL,         -- DIRECT, AGODA, BOOKING_COM, EXPEDIA, TRAVELOKA
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    dynamic_price DECIMAL(12,2) NOT NULL,       -- Mức giá động
    allotted_rooms INT DEFAULT 0,               -- Số phòng phân bổ cho kênh
    is_active BIT DEFAULT 1,
    created_at DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_rate_roomtype FOREIGN KEY (room_type_id) REFERENCES room_types(room_type_id)
);
GO

-- ============================================================================
-- PHẦN 3: KHÁCH HÀNG & ĐẶT PHÒNG (GUESTS & RESERVATIONS)
-- ============================================================================

-- 7. Bảng Khách hàng (UC.02.01, UC.03.01)
CREATE TABLE guests (
    guest_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    full_name NVARCHAR(100) NOT NULL,
    identity_card VARCHAR(30) NOT NULL UNIQUE,  -- Số CCCD, Hộ chiếu (Passport)
    phone VARCHAR(20) NOT NULL,
    email VARCHAR(100) NULL,
    nationality NVARCHAR(50) DEFAULT N'Việt Nam',
    guest_type NVARCHAR(20) DEFAULT N'REGULAR', -- REGULAR, VIP, CORPORATE
    created_at DATETIME2 DEFAULT GETDATE()
);
GO

-- 8. Bảng Phiếu đặt phòng (UC.02.01, UC.02.02)
CREATE TABLE bookings (
    booking_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    booking_code NVARCHAR(30) NOT NULL UNIQUE,  -- Mã booking (VD: BK-20261014-001)
    guest_id BIGINT NOT NULL,
    room_type_id BIGINT NOT NULL,
    channel NVARCHAR(30) DEFAULT N'DIRECT',     -- DIRECT, OTA, PHONE, WALK_IN
    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    total_rooms INT DEFAULT 1,
    deposit_amount DECIMAL(12,2) DEFAULT 0,     -- Tiền đặt cọc trước
    booking_status NVARCHAR(30) DEFAULT N'PENDING', -- PENDING, CONFIRMED, CANCELLED, COMPLETED
    special_requests NVARCHAR(MAX) NULL,
    created_at DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_book_guest FOREIGN KEY (guest_id) REFERENCES guests(guest_id),
    CONSTRAINT fk_book_type FOREIGN KEY (room_type_id) REFERENCES room_types(room_type_id)
);
GO

-- ============================================================================
-- PHẦN 4: LƯU TRÚ, DỊCH VỤ & THANH TOÁN (STAYS, SERVICES & BILLING)
-- ============================================================================

-- 9. Bảng Hồ sơ Lưu trú thực tế / Check-in Check-out (UC.03.01, UC.05.01)
CREATE TABLE room_stays (
    stay_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    booking_id BIGINT NULL,                     -- NULL nếu khách vãng lai (walk-in)
    room_id BIGINT NOT NULL,
    guest_id BIGINT NOT NULL,
    actual_check_in DATETIME2 DEFAULT GETDATE(),
    actual_check_out DATETIME2 NULL,
    assigned_key_card VARCHAR(64) NULL,         -- Thẻ từ cấp khi nhận phòng
    deposit_paid DECIMAL(12,2) DEFAULT 0,       -- Tiền cọc giữ lúc check-in
    stay_status NVARCHAR(30) DEFAULT N'CHECKED_IN', -- CHECKED_IN, CHECKED_OUT, EXTENDED
    created_by BIGINT NULL,                     -- Lễ tân thực hiện
    CONSTRAINT fk_stay_booking FOREIGN KEY (booking_id) REFERENCES bookings(booking_id),
    CONSTRAINT fk_stay_room FOREIGN KEY (room_id) REFERENCES rooms(room_id),
    CONSTRAINT fk_stay_guest FOREIGN KEY (guest_id) REFERENCES guests(guest_id),
    CONSTRAINT fk_stay_emp FOREIGN KEY (created_by) REFERENCES employees(employee_id)
);
GO

-- 10. Bảng Danh mục Dịch vụ & Tiện ích (UC.04.01)
CREATE TABLE services (
    service_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    service_code NVARCHAR(30) NOT NULL UNIQUE,  -- Mã DV (VD: SV-FNB-COFFEE, SV-SPA-BODY)
    service_name NVARCHAR(100) NOT NULL,
    category NVARCHAR(50) NOT NULL,             -- FNB, SPA, LAUNDRY, MINIBAR, TOUR, AIRPORT_SHUTTLE
    unit NVARCHAR(20) NOT NULL,                 -- Lần, Chai, Phần, Giờ...
    unit_price DECIMAL(12,2) NOT NULL,
    is_active BIT DEFAULT 1,
    created_at DATETIME2 DEFAULT GETDATE()
);
GO

-- 11. Bảng Chi tiết Dịch vụ khách sử dụng (UC.04.01, UC.05.01)
CREATE TABLE service_orders (
    order_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    stay_id BIGINT NOT NULL,
    service_id BIGINT NOT NULL,
    employee_id BIGINT NULL,                    -- Nhân viên F&B / Tiện ích ghi nhận
    quantity INT NOT NULL DEFAULT 1,
    unit_price DECIMAL(12,2) NOT NULL,
    total_amount DECIMAL(12,2) NOT NULL,
    order_time DATETIME2 DEFAULT GETDATE(),
    notes NVARCHAR(MAX) NULL,
    CONSTRAINT fk_svord_stay FOREIGN KEY (stay_id) REFERENCES room_stays(stay_id),
    CONSTRAINT fk_svord_service FOREIGN KEY (service_id) REFERENCES services(service_id),
    CONSTRAINT fk_svord_emp FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
);
GO

-- 12. Bảng Hóa đơn & Hóa đơn điện tử (UC.06.01, UC.17.01)
CREATE TABLE invoices (
    invoice_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    invoice_number NVARCHAR(50) NOT NULL UNIQUE,-- Mã số HĐ (VD: INV-20261014-001)
    stay_id BIGINT NOT NULL,
    room_charge DECIMAL(12,2) NOT NULL DEFAULT 0,
    service_charge DECIMAL(12,2) NOT NULL DEFAULT 0,
    discount_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    tax_vat_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    payment_status NVARCHAR(30) DEFAULT N'UNPAID', -- UNPAID, PARTIAL, PAID, REFUNDED
    einvoice_lookup_code NVARCHAR(100) NULL,    -- Mã tra cứu HĐĐT
    einvoice_signed_at DATETIME2 NULL,          -- Thời điểm ký số
    created_by BIGINT NULL,                     -- Kế toán / Thu ngân
    created_at DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_inv_stay FOREIGN KEY (stay_id) REFERENCES room_stays(stay_id),
    CONSTRAINT fk_inv_emp FOREIGN KEY (created_by) REFERENCES employees(employee_id)
);
GO

-- 13. Bảng Giao dịch Thanh toán (UC.06.01)
CREATE TABLE payments (
    payment_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    invoice_id BIGINT NOT NULL,
    payment_method NVARCHAR(50) NOT NULL,       -- CASH, CREDIT_CARD, BANK_TRANSFER, VNPAY, MOMO
    amount_paid DECIMAL(12,2) NOT NULL,
    transaction_reference NVARCHAR(100) NULL,   -- Mã giao dịch ngân hàng / cổng thanh toán
    paid_at DATETIME2 DEFAULT GETDATE(),
    received_by BIGINT NULL,                    -- Nhân viên thu ngân
    CONSTRAINT fk_pay_invoice FOREIGN KEY (invoice_id) REFERENCES invoices(invoice_id),
    CONSTRAINT fk_pay_emp FOREIGN KEY (received_by) REFERENCES employees(employee_id)
);
GO

-- ============================================================================
-- PHẦN 5: BUỒNG PHÒNG, KỸ THUẬT & AN NINH (HOUSEKEEPING, TECH & SECURITY)
-- ============================================================================

-- 14. Bảng Phân công & Kiểm tra Buồng phòng (UC.07.01, UC.07.02)
CREATE TABLE housekeeping_tasks (
    task_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    room_id BIGINT NOT NULL,
    assigned_to BIGINT NULL,                    -- Nhân viên buồng phòng dọn
    supervisor_id BIGINT NULL,                  -- Giám sát kiểm tra & nghiệm thu
    task_type NVARCHAR(30) NOT NULL,            -- DAILY_CLEAN, CHECKOUT_CLEAN, DEEP_CLEAN
    priority NVARCHAR(20) DEFAULT N'MEDIUM',    -- LOW, MEDIUM, HIGH, URGENT
    status NVARCHAR(30) DEFAULT N'PENDING',     -- PENDING, IN_PROGRESS, INSPECTED, COMPLETED, RE_CLEAN
    started_at DATETIME2 NULL,
    completed_at DATETIME2 NULL,
    inspection_notes NVARCHAR(MAX) NULL,
    CONSTRAINT fk_hk_room FOREIGN KEY (room_id) REFERENCES rooms(room_id),
    CONSTRAINT fk_hk_staff FOREIGN KEY (assigned_to) REFERENCES employees(employee_id),
    CONSTRAINT fk_hk_sup FOREIGN KEY (supervisor_id) REFERENCES employees(employee_id)
);
GO

-- 15. Bảng Phiếu yêu cầu Sửa chữa & Lịch bảo trì (UC.08.01, UC.08.02)
CREATE TABLE maintenance_tickets (
    ticket_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    room_id BIGINT NULL,                        -- Phòng hỏng (NULL nếu khu vực chung)
    area_name NVARCHAR(100) NULL,               -- Sảnh, Nhà hàng, Bể bơi, Thang máy...
    reported_by BIGINT NOT NULL,                -- Người báo hỏng
    assigned_technician_id BIGINT NULL,         -- Kỹ thuật viên phụ trách
    issue_description NVARCHAR(MAX) NOT NULL,
    priority NVARCHAR(20) DEFAULT N'MEDIUM',    -- LOW, MEDIUM, HIGH, EMERGENCY
    maintenance_type NVARCHAR(30) DEFAULT N'REPAIR', -- REPAIR, PREVENTIVE_MAINTENANCE
    status NVARCHAR(30) DEFAULT N'OPEN',        -- OPEN, IN_PROGRESS, RESOLVED, CLOSED
    scheduled_date DATE NULL,                   -- Lịch bảo trì định kỳ
    resolved_at DATETIME2 NULL,
    resolution_notes NVARCHAR(MAX) NULL,
    created_at DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_maint_room FOREIGN KEY (room_id) REFERENCES rooms(room_id),
    CONSTRAINT fk_maint_reporter FOREIGN KEY (reported_by) REFERENCES employees(employee_id),
    CONSTRAINT fk_maint_tech FOREIGN KEY (assigned_technician_id) REFERENCES employees(employee_id)
);
GO

-- 16. Bảng Báo cáo Sự cố & An ninh khách sạn (UC.14.01)
CREATE TABLE security_incidents (
    incident_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    incident_code NVARCHAR(30) NOT NULL UNIQUE, -- Mã sự cố (VD: INC-20261014-01)
    incident_type NVARCHAR(50) NOT NULL,        -- THEFT, DISTURBANCE, PROPERTY_DAMAGE, FIRE_ALARM, GUEST_ACCIDENT
    location NVARCHAR(100) NOT NULL,
    severity NVARCHAR(20) DEFAULT N'MEDIUM',    -- LOW, MEDIUM, HIGH, CRITICAL
    incident_time DATETIME2 NOT NULL,
    description NVARCHAR(MAX) NOT NULL,
    persons_involved NVARCHAR(MAX) NULL,
    reported_by BIGINT NOT NULL,                -- Nhân viên an ninh / nhân viên phát hiện
    action_taken NVARCHAR(MAX) NULL,            -- Biện pháp xử lý
    status NVARCHAR(30) DEFAULT N'REPORTED',    -- REPORTED, INVESTIGATING, RESOLVED, CLOSED
    closed_at DATETIME2 NULL,
    CONSTRAINT fk_sec_reporter FOREIGN KEY (reported_by) REFERENCES employees(employee_id)
);
GO

-- ============================================================================
-- PHẦN 6: KHO, MUA HÀNG, CSKH & THÔNG BÁO (INVENTORY, CS & NOTIFICATIONS)
-- ============================================================================

-- 17. Bảng Vật tư, Hàng hóa & Kiểm kê kho (UC.09.01)
CREATE TABLE inventory_items (
    item_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    item_code NVARCHAR(30) NOT NULL UNIQUE,     -- Mã vật tư (VD: VT-AMEN-SHAMPOO, VT-FNB-BEEF)
    item_name NVARCHAR(100) NOT NULL,
    category NVARCHAR(50) NOT NULL,             -- AMENITIES, LINEN, FNB_INGREDIENTS, CLEANING, HARDWARE
    unit NVARCHAR(20) NOT NULL,                 -- Chai, Bộ, Kg, Thùng, Hộp...
    quantity_in_stock DECIMAL(12,2) NOT NULL DEFAULT 0,
    minimum_threshold DECIMAL(12,2) NOT NULL DEFAULT 10, -- Mức tồn kho tối thiểu
    unit_cost DECIMAL(12,2) NOT NULL DEFAULT 0, -- Giá vốn đơn vị
    updated_at DATETIME2 DEFAULT GETDATE()
);
GO

-- 18. Bảng Đề nghị mua hàng & Nhập xuất kho (UC.09.01, UC.09.02)
CREATE TABLE purchase_orders (
    order_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    order_code NVARCHAR(30) NOT NULL UNIQUE,    -- Mã đơn chứng từ (VD: PO-20261014-01)
    item_id BIGINT NOT NULL,
    order_type NVARCHAR(30) NOT NULL,           -- PURCHASE_ORDER, STOCK_IN, STOCK_OUT, INVENTORY_AUDIT
    supplier_name NVARCHAR(100) NULL,           -- Tên nhà cung cấp
    quantity DECIMAL(12,2) NOT NULL,
    unit_price DECIMAL(12,2) NOT NULL,
    total_price DECIMAL(12,2) NOT NULL,
    requested_by BIGINT NOT NULL,               -- Nhân viên kho / F&B đề xuất
    approved_by BIGINT NULL,                    -- Quản lý khách sạn phê duyệt
    status NVARCHAR(30) DEFAULT N'DRAFT',       -- DRAFT, PENDING_APPROVAL, ORDERED, RECEIVED, CANCELLED
    created_at DATETIME2 DEFAULT GETDATE(),
    received_at DATETIME2 NULL,
    CONSTRAINT fk_po_item FOREIGN KEY (item_id) REFERENCES inventory_items(item_id),
    CONSTRAINT fk_po_req_emp FOREIGN KEY (requested_by) REFERENCES employees(employee_id),
    CONSTRAINT fk_po_appr_emp FOREIGN KEY (approved_by) REFERENCES employees(employee_id)
);
GO

-- 19. Bảng Phản hồi & Khiếu nại khách hàng (UC.13.01, UC.13.02)
CREATE TABLE customer_feedback (
    feedback_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    guest_id BIGINT NOT NULL,
    stay_id BIGINT NULL,                        -- Đợt lưu trú liên quan
    feedback_type NVARCHAR(30) NOT NULL,        -- COMPLIMENT, COMPLAINT, SUGGESTION
    content NVARCHAR(MAX) NOT NULL,
    rating INT NULL,                            -- Đánh giá 1 - 5 sao
    assigned_department NVARCHAR(50) NULL,      -- Bộ phận xử lý
    handler_id BIGINT NULL,                     -- Quản lý / Nhân viên giải quyết
    resolution NVARCHAR(MAX) NULL,              -- Phương án giải quyết
    status NVARCHAR(30) DEFAULT N'RECEIVED',    -- RECEIVED, IN_PROGRESS, RESOLVED, CLOSED
    created_at DATETIME2 DEFAULT GETDATE(),
    resolved_at DATETIME2 NULL,
    CONSTRAINT chk_feedback_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT fk_fb_guest FOREIGN KEY (guest_id) REFERENCES guests(guest_id),
    CONSTRAINT fk_fb_stay FOREIGN KEY (stay_id) REFERENCES room_stays(stay_id),
    CONSTRAINT fk_fb_handler FOREIGN KEY (handler_id) REFERENCES employees(employee_id)
);
GO

-- 20. Bảng Nhật ký gửi Thông báo Email / SMS / OTP (UC.16.01)
CREATE TABLE notifications (
    notification_id BIGINT IDENTITY(1,1) PRIMARY KEY,
    guest_id BIGINT NULL,
    booking_id BIGINT NULL,
    channel NVARCHAR(20) NOT NULL,              -- EMAIL, SMS, OTP
    recipient NVARCHAR(100) NOT NULL,           -- Email hoặc SĐT người nhận
    title NVARCHAR(150) NULL,
    content_body NVARCHAR(MAX) NOT NULL,
    status NVARCHAR(20) DEFAULT N'QUEUED',      -- QUEUED, SENT, FAILED
    sent_at DATETIME2 NULL,
    error_message NVARCHAR(MAX) NULL,
    created_at DATETIME2 DEFAULT GETDATE(),
    CONSTRAINT fk_notif_guest FOREIGN KEY (guest_id) REFERENCES guests(guest_id),
    CONSTRAINT fk_notif_booking FOREIGN KEY (booking_id) REFERENCES bookings(booking_id)
);
GO

-- ============================================================================
-- PHẦN 7: TẠO CHỈ MỤC TỐI ƯU TRUY VẤN (INDEXES)
-- ============================================================================
CREATE NONCLUSTERED INDEX idx_rooms_status ON rooms(status);
CREATE NONCLUSTERED INDEX idx_bookings_dates ON bookings(check_in_date, check_out_date);
CREATE NONCLUSTERED INDEX idx_bookings_code ON bookings(booking_code);
CREATE NONCLUSTERED INDEX idx_stays_status ON room_stays(stay_status);
CREATE NONCLUSTERED INDEX idx_invoices_status ON invoices(payment_status);
CREATE NONCLUSTERED INDEX idx_hk_status ON housekeeping_tasks(status);
CREATE NONCLUSTERED INDEX idx_maint_status ON maintenance_tickets(status);
CREATE NONCLUSTERED INDEX idx_inv_code ON inventory_items(item_code);
GO

-- ============================================================================
-- PHẦN 8: DỮ LIỆU MẪU BAN ĐẦU ĐỂ KIỂM THỬ (SEED DATA)
-- ============================================================================
SET IDENTITY_INSERT roles ON;
INSERT INTO roles (role_id, role_name, description) VALUES
(1, N'ADMIN', N'Quản trị viên toàn quyền hệ thống'),
(2, N'MANAGER', N'Người quản lý khách sạn'),
(3, N'RECEPTIONIST', N'Nhân viên lễ tân tiền sảnh'),
(4, N'HOUSEKEEPER', N'Nhân viên và giám sát buồng phòng'),
(5, N'ACCOUNTANT', N'Nhân viên kế toán tài chính');
SET IDENTITY_INSERT roles OFF;
GO

SET IDENTITY_INSERT room_types ON;
INSERT INTO room_types (room_type_id, type_name, base_price, max_adults, max_children, size_sqm, description) VALUES
(1, N'Standard Room', 650000, 2, 1, 25.0, N'Phòng tiêu chuẩn 1 giường đôi hoặc 2 giường đơn'),
(2, N'Deluxe City View', 1200000, 2, 1, 35.0, N'Phòng Deluxe hướng phố, bồn tắm nằm'),
(3, N'Suite Executive', 2500000, 3, 2, 60.0, N'Phòng Suite cao cấp có phòng khách riêng');
SET IDENTITY_INSERT room_types OFF;
GO

INSERT INTO rooms (room_type_id, room_number, floor, status, key_card_uid) VALUES
(1, N'101', 1, N'AVAILABLE', 'UID-CARD-101'),
(1, N'102', 1, N'AVAILABLE', 'UID-CARD-102'),
(2, N'201', 2, N'AVAILABLE', 'UID-CARD-201'),
(3, N'301', 3, N'AVAILABLE', 'UID-CARD-301');
GO

PRINT N'>>> HOÀN THÀNH TẠO 20 BẢNG CHO HỆ THỐNG QUẢN LÝ KHÁCH SẠN TRÊN SQL SERVER! <<<';
GO