SELECT fn_disponibilidad_asientos(1::bigint) AS asientos_disponibles;
SELECT fn_ingresos_funcion(1::bigint) AS ingresos_iniciales;

CALL sp_registrar_compra(1::bigint, 1::bigint, ARRAY[1, 2]::bigint[], 'Tarjeta');

SELECT * FROM pago WHERE idpago = 1;
SELECT * FROM tique WHERE idpago = 1 ORDER BY idtique;
SELECT fn_disponibilidad_asientos(1::bigint) AS asientos_despues_compra;
SELECT fn_ingresos_funcion(1::bigint) AS ingresos_despues_compra;

SELECT * FROM auditoria_ventas ORDER BY idauditoria;

CALL sp_registrar_compra(1::bigint, 2::bigint, ARRAY[4]::bigint[], 'Efectivo');

CALL sp_cancelar_compra(1::bigint);
SELECT * FROM pago WHERE idpago = 1;
SELECT * FROM tique WHERE idpago = 1 ORDER BY idtique;
SELECT fn_disponibilidad_asientos(1::bigint) AS asientos_tras_cancelar;
SELECT fn_ingresos_funcion(1::bigint) AS ingresos_tras_cancelar;