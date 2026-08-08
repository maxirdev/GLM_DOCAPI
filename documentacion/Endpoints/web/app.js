'use strict';

(function () {
  var nodoDatos = document.getElementById('endpoints-data');
  var datos = JSON.parse(nodoDatos.textContent);

  var cliente = 'LPS_COM';
  var fecha = formatearFecha(datos.meta.generatedAt);
  var total = datos.meta.totalConfirmed;

  var metadatos = document.getElementById('metadatos');
  metadatos.textContent = 'Cliente: ' + cliente + ' · Generado: ' + fecha + ' · Endpoints confirmados: ' + total;

  var cuerpoTabla = document.getElementById('cuerpo-tabla');
  var filtro = document.getElementById('filtro');
  var sinResultados = document.getElementById('sin-resultados');

  function formatearFecha(valor) {
    var fecha = new Date(valor);
    if (isNaN(fecha.getTime())) {
      return valor;
    }
    var dia = String(fecha.getDate()).padStart(2, '0');
    var mes = String(fecha.getMonth() + 1).padStart(2, '0');
    var anio = fecha.getFullYear();
    var horas = String(fecha.getHours()).padStart(2, '0');
    var minutos = String(fecha.getMinutes()).padStart(2, '0');
    return dia + '/' + mes + '/' + anio + ' ' + horas + ':' + minutos;
  }

  function normalizar(texto) {
    return texto
      .toLowerCase()
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '');
  }

  function crearFila(endpoint) {
    var fila = document.createElement('tr');

    var celdaNombre = document.createElement('td');
    celdaNombre.className = 'nombre izquierda';
    celdaNombre.textContent = endpoint.nombre;

    var celdaDescripcion = document.createElement('td');
    celdaDescripcion.className = 'izquierda';
    celdaDescripcion.textContent = endpoint.descripcion;

    fila.appendChild(celdaNombre);
    fila.appendChild(celdaDescripcion);
    return fila;
  }

  function renderizar(textoFiltro) {
    var termino = normalizar(textoFiltro);
    cuerpoTabla.innerHTML = '';
    var coincidencias = 0;

    datos.endpoints.forEach(function (endpoint) {
      var coincide =
        termino === '' ||
        normalizar(endpoint.nombre).indexOf(termino) !== -1 ||
        normalizar(endpoint.descripcion).indexOf(termino) !== -1;
      if (coincide) {
        cuerpoTabla.appendChild(crearFila(endpoint));
        coincidencias++;
      }
    });

    sinResultados.hidden = coincidencias !== 0;
  }

  filtro.addEventListener('input', function () {
    renderizar(filtro.value);
  });

  var alternarTema = document.getElementById('alternar-tema');
  var claveTema = 'visor-endpoints-tema';

  function aplicarTema(tema) {
    document.documentElement.setAttribute('data-theme', tema);
    alternarTema.textContent = tema === 'dark' ? 'Modo claro' : 'Modo oscuro';
  }

  alternarTema.addEventListener('click', function () {
    var actual = document.documentElement.getAttribute('data-theme');
    var siguiente = actual === 'dark' ? 'light' : 'dark';
    aplicarTema(siguiente);
    try {
      localStorage.setItem(claveTema, siguiente);
    } catch (error) {
      // localStorage bloqueado (p. ej. modo incógnito): el cambio vive solo en la sesión.
    }
  });

  var temaInicial = null;
  try {
    temaInicial = localStorage.getItem(claveTema);
  } catch (error) {
    temaInicial = null;
  }
  if (temaInicial !== 'dark' && temaInicial !== 'light') {
    temaInicial =
      window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }
  aplicarTema(temaInicial);

  renderizar('');
})();
