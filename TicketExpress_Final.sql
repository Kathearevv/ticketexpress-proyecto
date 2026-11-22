-- =========================================================================
-- PROYECTO: TICKETEXPRESS+ (POSTGRESQL)
-- SCRIPT UNIFICADO DE ESQUEMA, DATOS INICIALES, FUNCIONES, PROCEDIMIENTOS Y TRIGGERS
-- =========================================================================

-- -------------------------------------------------------------------------
-- PARTE 1 (COMPAÑEROS - INTEGRANTE 1 / EQUIPO BASE): SECUENCIAS Y TABLAS
-- -------------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS seq_pago START WITH 1 INCREMENT BY 1;
CREATE SEQUENCE IF NOT EXISTS seq_tique START WITH 1 INCREMENT BY 1;

CREATE TABLE IF NOT EXISTS categoria (
    idcategoria BIGSERIAL PRIMARY KEY,
    nombre      VARCHAR(80) NOT NULL UNIQUE,
    descripcion VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS recinto (
    idrecinto BIGSERIAL PRIMARY KEY,
    nombre    VARCHAR(120) NOT NULL,
    ciudad    VARCHAR(100) NOT NULL,
    direccion VARCHAR(255) NOT NULL,
    capacidad INTEGER NOT NULL CHECK (capacidad > 0)
);

CREATE TABLE IF NOT EXISTS usuario (
    idusuario        BIGSERIAL PRIMARY KEY,
    nombre_completo  VARCHAR(150) NOT NULL,
    correo           VARCHAR(150) NOT NULL UNIQUE,
    telefono         VARCHAR(30),
    fecha_registro   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS evento (
    idevento     BIGSERIAL PRIMARY KEY,
    idcategoria  BIGINT NOT NULL REFERENCES categoria(idcategoria),
    idrecinto    BIGINT NOT NULL REFERENCES recinto(idrecinto),
    titulo       VARCHAR(160) NOT NULL,
    descripcion  TEXT,
    estado       VARCHAR(30) NOT NULL DEFAULT 'ACTIVO'
);

CREATE TABLE IF NOT EXISTS funcion (
    idfuncion    BIGSERIAL PRIMARY KEY,
    idevento     BIGINT NOT NULL REFERENCES evento(idevento) ON DELETE CASCADE,
    fecha_hora   TIMESTAMP NOT NULL,
    estado       VARCHAR(30) NOT NULL DEFAULT 'PROGRAMADA'
);

CREATE TABLE IF NOT EXISTS asiento (
    idasiento    BIGSERIAL PRIMARY KEY,
    idrecinto    BIGINT NOT NULL REFERENCES recinto(idrecinto) ON DELETE CASCADE,
    zona         VARCHAR(60) NOT NULL,
    fila         VARCHAR(15) NOT NULL,
    numero       VARCHAR(15) NOT NULL,
    estado       VARCHAR(30) NOT NULL DEFAULT 'DISPONIBLE',
    UNIQUE (idrecinto, zona, fila, numero)
);

CREATE TABLE IF NOT EXISTS tarifa (
    idtarifa     BIGSERIAL PRIMARY KEY,
    idfuncion    BIGINT NOT NULL REFERENCES funcion(idfuncion) ON DELETE CASCADE,
    nombre       VARCHAR(80) NOT NULL,
    precio       NUMERIC(10, 2) NOT NULL CHECK (precio >= 0),
    activa       BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS pago (
    idpago         BIGINT PRIMARY KEY DEFAULT nextval('seq_pago'),
    idusuario      BIGINT NOT NULL REFERENCES usuario(idusuario),
    monto_total    NUMERIC(12, 2) NOT NULL CHECK (monto_total >= 0),
    metodo_pago    VARCHAR(40) NOT NULL,
    estado         VARCHAR(30) NOT NULL DEFAULT 'PAGADO',
    fecha_pago     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS tique (
    idtique        BIGINT PRIMARY KEY DEFAULT nextval('seq_tique'),
    idpago         BIGINT NOT NULL REFERENCES pago(idpago),
    idfuncion      BIGINT NOT NULL REFERENCES funcion(idfuncion),
    idasiento      BIGINT NOT NULL REFERENCES asiento(idasiento),
    idtarifa       BIGINT NOT NULL REFERENCES tarifa(idtarifa),
    preciopagado   NUMERIC(10, 2) NOT NULL CHECK (preciopagado >= 0),
    estado         VARCHAR(30) NOT NULL DEFAULT 'ACTIVO',
    fecha_emision  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (idfuncion, idasiento)
);

CREATE TABLE IF NOT EXISTS auditoria_ventas (
    idauditoria    BIGSERIAL PRIMARY KEY,
    idtique        BIGINT NOT NULL,
    idpago         BIGINT NOT NULL,
    idfuncion      BIGINT NOT NULL,
    idasiento      BIGINT NOT NULL,
    preciopagado   NUMERIC(10, 2) NOT NULL,
    accion         VARCHAR(30) NOT NULL,
    usuario_db     VARCHAR(100) NOT NULL DEFAULT CURRENT_USER,
    fecha_registro TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- -------------------------------------------------------------------------
-- PARTE 2 (COMPAÑEROS - INTEGRANTE 1 / EQUIPO BASE): DATOS SEMILLA
-- -------------------------------------------------------------------------
INSERT INTO categoria (nombre, descripcion) VALUES
    ('Conciertos', 'Presentaciones musicales en vivo'),
    ('Teatro', 'Obras teatrales y artes escénicas')
ON CONFLICT (nombre) DO NOTHING;

INSERT INTO recinto (nombre, ciudad, direccion, capacidad) VALUES
    ('Teatro Nacional', 'San Salvador', 'Calle Delgado, Centro Histórico', 3),
    ('Auditorio Principal', 'Santa Tecla', 'Paseo El Carmen', 100)
ON CONFLICT DO NOTHING;

INSERT INTO usuario (nombre_completo, correo, telefono) VALUES
    ('Katherine Arévalo', 'katherine.test@ticketexpress.sv', '7000-0001'),
    ('Carlos Mejía', 'carlos.test@ticketexpress.sv', '7000-0002')
ON CONFLICT (correo) DO NOTHING;

INSERT INTO evento (idcategoria, idrecinto, titulo, descripcion, estado) VALUES
    (1, 1, 'Noche Acústica', 'Concierto íntimo en vivo', 'ACTIVO'),
    (2, 1, 'Clásicos de Noviembre', 'Función teatral retrospectiva', 'ACTIVO')
ON CONFLICT DO NOTHING;

-- Función 1: Futura (para pruebas de compra y cancelación)
-- Función 2: Pasada (para probar trigger de validación de tiempo de venta)
INSERT INTO funcion (idevento, fecha_hora, estado) VALUES
    (1, CURRENT_TIMESTAMP + INTERVAL '7 days', 'PROGRAMADA'),
    (2, CURRENT_TIMESTAMP - INTERVAL '2 days', 'FINALIZADA')
ON CONFLICT DO NOTHING;

-- 3 asientos en Recinto 1 para probar disponibilidad inicial = 3
INSERT INTO asiento (idrecinto, zona, fila, numero, estado) VALUES
    (1, 'VIP', 'A', '1', 'DISPONIBLE'),
    (1, 'VIP', 'A', '2', 'DISPONIBLE'),
    (1, 'General', 'B', '1', 'DISPONIBLE')
ON CONFLICT (idrecinto, zona, fila, numero) DO NOTHING;

-- Tarifas: 1 y 2 para función 1; 4 para función 2
INSERT INTO tarifa (idfuncion, nombre, precio, activa) VALUES
    (1, 'Entrada General', 25.00, TRUE),
    (1, 'Entrada Preferencial', 40.00, TRUE),
    (1, 'Estudiante', 15.00, TRUE),
    (2, 'Entrada Única', 20.00, TRUE)
ON CONFLICT DO NOTHING;

-- -------------------------------------------------------------------------
-- PARTE 3 (COMPAÑEROS - INTEGRANTE 1): FUNCIONES DE CONSULTA
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_disponibilidad_asientos(p_idfuncion bigint)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_asientos BIGINT := 0;
    v_ocupados       BIGINT := 0;
BEGIN
    SELECT COUNT(a.idasiento)
    INTO v_total_asientos
    FROM funcion f
    INNER JOIN evento e ON e.idevento = f.idevento
    INNER JOIN asiento a ON a.idrecinto = e.idrecinto
    WHERE f.idfuncion = p_idfuncion;

    SELECT COUNT(t.idtique)
    INTO v_ocupados
    FROM tique t
    WHERE t.idfuncion = p_idfuncion
      AND t.estado <> 'CANCELADO';

    RETURN GREATEST(v_total_asientos - v_ocupados, 0);
END;
$$;

CREATE OR REPLACE FUNCTION fn_ingresos_funcion(p_idfuncion bigint)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_total NUMERIC(12, 2) := 0;
BEGIN
    SELECT COALESCE(SUM(t.preciopagado), 0)
    INTO v_total
    FROM tique t
    INNER JOIN pago p ON p.idpago = t.idpago
    WHERE t.idfuncion = p_idfuncion
      AND t.estado <> 'CANCELADO'
      AND p.estado = 'PAGADO';

    RETURN v_total;
END;
$$;

-- -------------------------------------------------------------------------
-- PARTE 4 (TU APORTE - INTEGRANTE 3): PROCEDIMIENTOS Y TRIGGERS
-- -------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_registrar_compra(
    p_idusuario   bigint,
    p_idfuncion   bigint,
    p_idtarifas   bigint[],
    p_metodo_pago varchar
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_idpago          BIGINT;
    v_monto_total     NUMERIC(12, 2) := 0;
    v_idtarifa        BIGINT;
    v_precio_tarifa   NUMERIC(10, 2);
    v_idrecinto       BIGINT;
    v_idasiento       BIGINT;
    v_cant_solicitada INT;
    v_disponibles     BIGINT;
BEGIN
    IF p_idtarifas IS NULL OR array_length(p_idtarifas, 1) IS NULL THEN
        RAISE EXCEPTION 'Debe indicar al menos una tarifa para registrar la compra.';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM usuario WHERE idusuario = p_idusuario) THEN
        RAISE EXCEPTION 'El usuario % no existe.', p_idusuario;
    END IF;

    SELECT e.idrecinto
    INTO v_idrecinto
    FROM funcion f
    INNER JOIN evento e ON e.idevento = f.idevento
    WHERE f.idfuncion = p_idfuncion;

    IF v_idrecinto IS NULL THEN
        RAISE EXCEPTION 'La función % no existe.', p_idfuncion;
    END IF;

    v_cant_solicitada := array_length(p_idtarifas, 1);
    v_disponibles := fn_disponibilidad_asientos(p_idfuncion);

    IF v_disponibles < v_cant_solicitada THEN
        RAISE EXCEPTION 'No hay suficientes asientos disponibles para la función % (solicitados: %, disponibles: %).',
            p_idfuncion, v_cant_solicitada, v_disponibles;
    END IF;

    -- Calcular monto total verificando tarifas válidas para la función
    FOREACH v_idtarifa IN ARRAY p_idtarifas
    LOOP
        SELECT precio
        INTO v_precio_tarifa
        FROM tarifa
        WHERE idtarifa = v_idtarifa
          AND idfuncion = p_idfuncion
          AND activa = TRUE;

        IF v_precio_tarifa IS NULL THEN
            RAISE EXCEPTION 'La tarifa % no es válida o no pertenece a la función %.', v_idtarifa, p_idfuncion;
        END IF;

        v_monto_total := v_monto_total + v_precio_tarifa;
    END LOOP;

    INSERT INTO pago (idusuario, monto_total, metodo_pago, estado)
    VALUES (p_idusuario, v_monto_total, p_metodo_pago, 'PAGADO')
    RETURNING idpago INTO v_idpago;

    FOREACH v_idtarifa IN ARRAY p_idtarifas
    LOOP
        SELECT precio
        INTO v_precio_tarifa
        FROM tarifa
        WHERE idtarifa = v_idtarifa;

        SELECT a.idasiento
        INTO v_idasiento
        FROM asiento a
        WHERE a.idrecinto = v_idrecinto
          AND a.estado = 'DISPONIBLE'
          AND NOT EXISTS (
              SELECT 1
              FROM tique t
              WHERE t.idfuncion = p_idfuncion
                AND t.idasiento = a.idasiento
                AND t.estado <> 'CANCELADO'
          )
        ORDER BY a.idasiento
        LIMIT 1
        FOR UPDATE SKIP LOCKED;

        IF v_idasiento IS NULL THEN
            RAISE EXCEPTION 'No se pudo asignar un asiento disponible para la función %.', p_idfuncion;
        END IF;

        INSERT INTO tique (idpago, idfuncion, idasiento, idtarifa, preciopagado, estado)
        VALUES (v_idpago, p_idfuncion, v_idasiento, v_idtarifa, v_precio_tarifa, 'ACTIVO');

        UPDATE asiento
        SET estado = 'RESERVADO'
        WHERE idasiento = v_idasiento;
    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE sp_cancelar_compra(p_idpago bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pago WHERE idpago = p_idpago) THEN
        RAISE EXCEPTION 'El pago % no existe.', p_idpago;
    END IF;

    IF EXISTS (SELECT 1 FROM pago WHERE idpago = p_idpago AND estado = 'CANCELADO') THEN
        RAISE EXCEPTION 'El pago % ya se encuentra cancelado.', p_idpago;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM tique WHERE idpago = p_idpago) THEN
        RAISE EXCEPTION 'No hay tiques asociados al pago %.', p_idpago;
    END IF;

    UPDATE asiento a
    SET estado = 'DISPONIBLE'
    FROM tique t
    WHERE t.idasiento = a.idasiento
      AND t.idpago = p_idpago
      AND t.estado <> 'CANCELADO';

    UPDATE tique
    SET estado = 'CANCELADO'
    WHERE idpago = p_idpago;

    UPDATE pago
    SET estado = 'CANCELADO'
    WHERE idpago = p_idpago;
END;
$$;

CREATE OR REPLACE FUNCTION fn_trigger_auditoria_ventas()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO auditoria_ventas (
        idtique,
        idpago,
        idfuncion,
        idasiento,
        preciopagado,
        accion
    )
    VALUES (
        NEW.idtique,
        NEW.idpago,
        NEW.idfuncion,
        NEW.idasiento,
        NEW.preciopagado,
        'INSERT_TIQUE'
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auditoria_ventas ON tique;
CREATE TRIGGER trg_auditoria_ventas
AFTER INSERT ON tique
FOR EACH ROW
EXECUTE FUNCTION fn_trigger_auditoria_ventas();

CREATE OR REPLACE FUNCTION fn_trigger_validar_tiempo_venta()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_fecha_funcion TIMESTAMP;
    v_estado_funcion VARCHAR(30);
BEGIN
    SELECT fecha_hora, estado
    INTO v_fecha_funcion, v_estado_funcion
    FROM funcion
    WHERE idfuncion = NEW.idfuncion;

    IF v_fecha_funcion IS NULL THEN
        RAISE EXCEPTION 'La función % no existe.', NEW.idfuncion;
    END IF;

    IF v_fecha_funcion <= CURRENT_TIMESTAMP OR UPPER(v_estado_funcion) IN ('FINALIZADA', 'CANCELADA') THEN
        RAISE EXCEPTION 'No se pueden vender tiques para la función % porque ya ocurrió o no está disponible.', NEW.idfuncion;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_tiempo_venta ON tique;
CREATE TRIGGER trg_validar_tiempo_venta
BEFORE INSERT ON tique
FOR EACH ROW
EXECUTE FUNCTION fn_trigger_validar_tiempo_venta();