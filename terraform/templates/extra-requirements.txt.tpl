-r base-requirements.txt

%{ for requirement in extra_requirements ~}
${requirement}
%{ endfor ~}
