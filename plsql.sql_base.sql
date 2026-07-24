-- 03_plsql.sql
DELIMITER //

-- ==========================================
-- 4.1 Triggers (Mínimo 2)
-- ==========================================

-- Trigger 1: Regla de Negocio: Validar transiciones de estado lógicas.
-- Un préstamo marcado como 'Devuelto' no puede retroceder a 'Activo' o 'Solicitado'.
-- Evento: BEFORE UPDATE.
-- Caso de prueba positivo: UPDATE PRESTAMO SET estado_prestamo = 'Devuelto' WHERE estado_prestamo = 'Activo';
-- Caso de prueba negativo: UPDATE PRESTAMO SET estado_prestamo = 'Activo' WHERE estado_prestamo = 'Devuelto';
CREATE TRIGGER trg_validar_estado_prestamo
BEFORE UPDATE ON PRESTAMO
FOR EACH ROW
BEGIN
    IF OLD.estado_prestamo = 'Devuelto' AND NEW.estado_prestamo IN ('Activo', 'Solicitado') THEN
        SIGNAL SQLSTATE '45000' 
        SET MESSAGE_TEXT = 'Transición de estado inválida: Un préstamo devuelto no puede reactivarse.';
    END IF;
END //

-- Trigger 2: Regla de Negocio: Auditoría automática.
-- Registrar automáticamente en la tabla AUDITORIA_TRANSACCIONES cada nueva sanción aplicada.
-- Evento: AFTER INSERT.
CREATE TRIGGER trg_auditar_sancion
AFTER INSERT ON SANCION
FOR EACH ROW
BEGIN
    INSERT INTO AUDITORIA_TRANSACCIONES 
    (id_prestamo, id_administrador, tipo_evento, detalle_evento, usuario_auditor)
    VALUES 
    (NEW.id_prestamo, NEW.id_administrador, 'NUEVA_SANCION', CONCAT('Sanción ID: ', NEW.id_sancion, ' aplicada al usuario ', NEW.id_usuario, '. Motivo: ', NEW.motivo), CURRENT_USER());
END

-- ==========================================
-- 4.3 Funciones (Mínimo 2)
-- ==========================================

-- Función 1: Calcular el total facturado por un vendedor específico.
CREATE FUNCTION fn_total_ventas_vendedor(p_id_vendedor INT) 
RETURNS DECIMAL(15,2)
DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(15,2) DEFAULT 0.00;
    SELECT COALESCE(SUM(c.monto_total), 0) INTO v_total
    FROM COMPRA c
    JOIN PUBLICACION p ON c.id_publicacion = p.id_publicacion
    WHERE p.id_vendedor = p_id_vendedor;
    RETURN v_total;
END //

-- Función 2: Obtener el porcentaje de productos usados frente al total del catálogo de un vendedor.
CREATE FUNCTION fn_porcentaje_usados(p_id_vendedor INT) 
RETURNS DECIMAL(5,2)
DETERMINISTIC
BEGIN
    DECLARE v_total_productos INT;
    DECLARE v_total_usados INT;
    DECLARE v_porcentaje DECIMAL(5,2) DEFAULT 0.00;
    
    SELECT COUNT(*) INTO v_total_productos 
    FROM PRODUCTO pr JOIN PUBLICACION pu ON pr.id_publicacion = pu.id_publicacion WHERE pu.id_vendedor = p_id_vendedor;
    
    SELECT COUNT(*) INTO v_total_usados 
    FROM PRODUCTO pr JOIN PUBLICACION pu ON pr.id_publicacion = pu.id_publicacion WHERE pu.id_vendedor = p_id_vendedor AND pr.estado_fisico = 'USADO';
    
    IF v_total_productos > 0 THEN
        SET v_porcentaje = (v_total_usados / v_total_productos) * 100;
    END IF;
    
    RETURN v_porcentaje;
END //

-- ==========================================
-- 4.2 Procedimientos (Mínimo 2, uno con Cursores y Excepciones)
-- ==========================================

-- Procedimiento 1: Transacción completa que inserta una compra y deduce el stock del producto.
CREATE PROCEDURE prc_registrar_compra(
    IN p_id_comprador INT, 
    IN p_id_publicacion INT, 
    IN p_metodo_pago VARCHAR(50)
)
BEGIN
    DECLARE v_precio DECIMAL(15,2);
    DECLARE v_stock INT;
    
    -- Manejo de excepciones básico
    DECLARE EXIT HANDLER FOR SQLEXCEPTION 
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    
    SELECT precio, stock INTO v_precio, v_stock 
    FROM PRODUCTO WHERE id_publicacion = p_id_publicacion FOR UPDATE;
    
    IF v_stock > 0 THEN
        INSERT INTO COMPRA (id_comprador, id_publicacion, monto_total, metodo_pago)
        VALUES (p_id_comprador, p_id_publicacion, v_precio, p_metodo_pago);
        
        UPDATE PRODUCTO SET stock = stock - 1 WHERE id_publicacion = p_id_publicacion;
        COMMIT;
    ELSE
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stock insuficiente para procesar la compra.';
    END IF;
END //

-- Procedimiento 2 (Cumple requisito de complejidad): Cierre masivo de trueques inactivos usando Cursor y Excepciones.
CREATE PROCEDURE prc_limpiar_trueques_vencidos()
BEGIN
    DECLARE v_id_trueque INT;
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_errores INT DEFAULT 0;
    
    -- Cursor para iterar trueques antiguos
    DECLARE cur_trueques CURSOR FOR 
        SELECT id_trueque FROM TRUEQUE WHERE estado_trueque = 'Pendiente' AND fecha_propuesta < DATE_SUB(NOW(), INTERVAL 30 DAY);
        
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;
    
    -- Excepción para continuar incluso si un update falla
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION SET v_errores = v_errores + 1;

    OPEN cur_trueques;
    
    read_loop: LOOP
        FETCH cur_trueques INTO v_id_trueque;
        IF v_done THEN
            LEAVE read_loop;
        END IF;
        
        UPDATE TRUEQUE SET estado_trueque = 'Rechazado' WHERE id_trueque = v_id_trueque;
    END LOOP;
    
    CLOSE cur_trueques;
    
    -- Si hubo errores, dejar registro en log de base de datos (simulado aquí)
    IF v_errores > 0 THEN
        SELECT CONCAT('Finalizado con ', v_errores, ' errores procesados.');
    END IF;
END //

DELIMITER ;
