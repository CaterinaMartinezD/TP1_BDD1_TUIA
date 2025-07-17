---------------------------------------------------------------------------
-------CREA LA BASE DE DATOS-----------------------------------------------
---------------------------------------------------------------------------
CREATE DATABASE TP_BDD2_TUIA_2025
GO
USE [TP_BDD2_TUIA_2025]
GO
---------------------------------------------------------------------------
-------GENERA LAS TABLAS---------------------------------------------------
---------------------------------------------------------------------------
CREATE TABLE D_Fecha(
    ID_fecha INT PRIMARY KEY NOT NULL IDENTITY(1,1),
    Fecha DATE NOT NULL UNIQUE,
    Dia INT NOT NULL,
    Mes INT NOT NULL,
    Nombre_mes VARCHAR(50) NOT NULL,
    Dia_del_anio INT NOT NULL,
    Dia_de_semana INT NOT NULL,
    Nombre_dia_de_semana VARCHAR(50) NOT NULL,
    Dias_habiles VARCHAR(50) NOT NULL,
    Feriado VARCHAR(50) NOT NULL,
    Nombre_feriado VARCHAR(50),
    Trimestre INT NOT NULL,
    Semestre INT NOT NULL
);

CREATE TABLE D_Region(
    Region VARCHAR(50) NOT NULL,
    Estado VARCHAR(50) NOT NULL,
    Ciudad VARCHAR(50) NOT NULL,
    Codigo_postal INT NOT NULL PRIMARY KEY
);

CREATE TABLE D_Cliente(
    ID_cliente INT PRIMARY KEY NOT NULL,
    Nombre_cliente VARCHAR(50) NOT NULL,
    Fecha_de_nacimiento  DATE NOT NULL,
    Tipo_de_cliente VARCHAR(50) NOT NULL,
    Codigo_postal INT NOT NULL,
    FOREIGN KEY (Codigo_postal) REFERENCES D_Region(Codigo_postal)
);

CREATE TABLE D_Producto(
    ID_producto INT PRIMARY KEY IDENTITY(1,1),
    Nombre_producto VARCHAR(50) NOT NULL,
    Capacidad_en_Litro VARCHAR(50) NOT NULL,
);

CREATE TABLE D_Stock(
    ID_Stock INT PRIMARY KEY IDENTITY(1,1),
    ID_producto INT NOT NULL,
    Fecha_stock VARCHAR(50) NOT NULL, 
    Cantidad_stock INT NOT NULL,
    FOREIGN KEY (ID_producto) REFERENCES D_Producto(ID_producto)
);

CREATE TABLE D_Precio(
	ID_Precio INT PRIMARY KEY NOT NULL IDENTITY(1,1),
    ID_Producto INT NOT NULL,
    Fecha DATE NOT NULL,
    Precio FLOAT NOT NULL,
    FOREIGN KEY (ID_Producto) REFERENCES D_Producto(ID_producto)
);

CREATE TABLE D_Empleado(
	ID_empleado INT PRIMARY KEY NOT NULL IDENTITY(1,1),
	Nombre_empleado VARCHAR(100) NOT NULL,
	Categoria VARCHAR(50),
	Fecha_ingreso DATE NOT NULL,
	Fecha_de_nacimiento DATE NOT NULL,
	Nivel_educacion VARCHAR(50) NOT NULL,
	Genero VARCHAR(50) NOT NULL,
);

CREATE TABLE D_Descuento (
    ID_descuento INT PRIMARY KEY NOT NULL IDENTITY(1,1),
    Fecha_inicio DATE NOT NULL,
    Fecha_final DATE,
    Porcentaje FLOAT NULL,
    Total_factura FLOAT NULL
);

CREATE TABLE H_Factura (
    ID_factura INT PRIMARY KEY NOT NULL,
    ID_empleado INT NOT NULL,
    ID_cliente INT NOT NULL,
    ID_branch INT,
    Monto FLOAT,
    ID_descuento INT,
    Monto_descuento FLOAT,
	Monto_total FLOAT,
    Fecha_de_factura DATE NOT NULL,
    FOREIGN KEY (ID_empleado) REFERENCES D_Empleado(ID_empleado),
    FOREIGN KEY (ID_cliente) REFERENCES D_Cliente(ID_cliente),
    FOREIGN KEY (ID_descuento) REFERENCES D_Descuento(ID_descuento),
    FOREIGN KEY (Fecha_de_factura) REFERENCES D_Fecha(Fecha)
);

CREATE TABLE H_Factura_Detalle(
    ID_detalle INT PRIMARY KEY NOT NULL IDENTITY(1,1),
    ID_factura INT NOT NULL,
    ID_producto INT NOT NULL,
    Cantidad INT NOT NULL,
    FOREIGN KEY (ID_factura) REFERENCES H_Factura(ID_factura),
	FOREIGN KEY (ID_producto) REFERENCES D_producto(ID_Producto)
);

---------------------------------------------------------------------------
-------GENERA VISTAS-------------------------------------------------------
---------------------------------------------------------------------------

--REALIZA EL CALCULO PARA EL MONTO TOTAL DE UNA FACTURA
CREATE VIEW V_Monto_Factura AS
SELECT HD.ID_factura,SUM(HD.Cantidad * D.Precio) AS Monto
FROM H_Factura_Detalle HD
INNER JOIN H_Factura HF ON HD.ID_factura = HF.ID_factura
INNER JOIN D_Precio D ON HD.ID_producto = D.ID_Producto 
		   AND D.Fecha = (SELECT MAX(Fecha)FROM D_Precio DP WHERE DP.ID_Producto = HD.ID_producto
           AND DP.Fecha <= HF.Fecha_de_factura)
GROUP BY HD.ID_factura;

--Realiza el calculo del porcentaje de descuento al cual accede el cliente
CREATE VIEW V_Porcenaje_Descuento AS
SELECT HF.ID_factura,HF.Monto, D.ID_descuento AS Porcentaje_Descuento
FROM H_Factura HF
INNER JOIN D_Descuento D ON HF.Monto >= D.Total_factura
WHERE HF.Fecha_de_factura BETWEEN D.Fecha_inicio AND ISNULL(D.Fecha_final, HF.Fecha_de_factura)
  AND D.Porcentaje = (SELECT MAX(D1.Porcentaje) FROM D_Descuento D1 WHERE HF.Monto >= D1.Total_factura
  AND HF.Fecha_de_factura BETWEEN D1.Fecha_inicio AND ISNULL(D1.Fecha_final, HF.Fecha_de_factura));

--Obtiene el monto total con el descuento aplicado
CREATE VIEW V_Monto_Descuento AS
SELECT HF.ID_factura, HF.Monto, HF.ID_descuento,
	  (HF.Monto - (HF.Monto * (D.Porcentaje / 100))) AS Monto_con_Descuento
FROM H_Factura HF
INNER JOIN D_Descuento D ON HF.ID_descuento = D.ID_descuento;

--Obtiene el monto total con el descuento aplicado
CREATE VIEW V_Monto_Total AS
SELECT HF.ID_factura, ISNULL(HF.Monto_descuento, HF.Monto) AS Monto_total
FROM H_Factura HF;

--ACTUALIZA LA COLUMNA Monto
UPDATE HF
SET HF.Monto = V.Monto
FROM H_Factura HF
INNER JOIN V_Monto_Factura V ON HF.ID_factura = V.ID_factura;

--ELIMINA LAS FACTURAS QUE TIENEN NULL EN MONTO. DE 319.067 FACTURAS ELIMINA 47.763 => 273.297
--LAS DEL 2006 SON DEL MES DE ENERO QUE NO TENIAN FECHA TODAVIA LOS PRODUCTOS
DELETE FROM H_Factura_Detalle
WHERE ID_factura IN (SELECT ID_factura FROM H_Factura WHERE Monto IS NULL);
--ALGUNOS DEL 2009 NO TIENEN DETALLE DE FACTURA, POR ENDE NO SE PUEDE CALCULAR EL MONTO
DELETE FROM H_Factura
WHERE Monto IS NULL;

--ACTUALIZA LA COLUMNA ID descuento
UPDATE HF
SET HF.ID_descuento = VD.Porcentaje_Descuento
FROM H_Factura HF
INNER JOIN V_Porcenaje_Descuento VD ON HF.ID_factura = VD.ID_factura;

--ACTUALIZA LA COLUMNA Monto Descuento
UPDATE HF
SET HF.Monto_descuento = VMD.Monto_con_Descuento
FROM H_Factura HF
INNER JOIN V_Monto_Descuento VMD ON HF.ID_factura = VMD.ID_factura;

--ACTUALIZA LA COLUMNA Monto Total
UPDATE HF
SET HF.Monto_total = VMT.Monto_total
FROM H_Factura HF
INNER JOIN V_Monto_Total VMT ON HF.ID_factura = VMT.ID_factura;